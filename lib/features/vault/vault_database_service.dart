import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'vault_item.dart';

/// قاعدة بيانات محلية مشفّرة بالكامل (SQLCipher عن طريق
/// `sqflite_sqlcipher`) بتخزّن بس *ميتاداتا* عناصر الخزنة (نوع، مسار
/// الملف المشفّر الأصلي، ثامبنيل صغير، تاريخ، مدة الفيديو).
///
/// مفتاح تشفير قاعدة البيانات نفسها (DB passphrase) مختلف تمامًا عن
/// مفتاح RSA بتاع تشفير الصور/الفيديوهات - ده مفتاح symmetric عشوائي
/// بيتولد مرة واحدة أول ما التطبيق يشتغل، ومتخزن في secure storage
/// (Keystore/Keychain). حتى لو حد وصل لملف الـ .db على القرص مباشرة،
/// مش هيقدر يفتحه من غير المفتاح ده.
class VaultDatabaseService {
  static const _dbPassphraseKey = 'vault_db_passphrase_v1';
  static const _dbFileName = 'vault_meta.db';
  static const _storage = FlutterSecureStorage();

  static Database? _db;

  /// بيرجّع اتصال قاعدة البيانات، وبيفتحه أول مرة لو لسه مش مفتوح.
  static Future<Database> _open() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final passphrase = await _getOrCreatePassphrase();
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbFileName);

    final db = await openDatabase(
      dbPath,
      password: passphrase,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vault_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            original_file_path TEXT NOT NULL,
            thumbnail_blob BLOB NOT NULL,
            date_created INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_vault_items_date ON vault_items(date_created DESC)',
        );
      },
    );

    _db = db;
    return db;
  }

  static Future<String> _getOrCreatePassphrase() async {
    final existing = await _storage.read(key: _dbPassphraseKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final secureRandom = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => secureRandom.nextInt(256)),
    );
    final passphrase = base64UrlEncode(bytes);

    await _storage.write(key: _dbPassphraseKey, value: passphrase);
    return passphrase;
  }

  /// جلب صفحة من عناصر الخزنة، الأحدث الأول.
  static Future<List<VaultItem>> fetchPage({
    required int limit,
    required int offset,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'vault_items',
      orderBy: 'date_created DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((row) => VaultItem.fromMap(row)).toList();
  }

  /// إضافة عنصر جديد للخزنة، وبيرجّع نفس العنصر بس بـ id الحقيقي بعد
  /// الإدراج.
  static Future<VaultItem> insertItem({
    required VaultItemType type,
    required String originalFilePath,
    required Uint8List thumbnailBlob,
    required DateTime dateCreated,
    int durationMs = 0,
  }) async {
    final db = await _open();
    final id = await db.insert('vault_items', {
      'type': type == VaultItemType.video ? 'video' : 'photo',
      'original_file_path': originalFilePath,
      'thumbnail_blob': thumbnailBlob,
      'date_created': dateCreated.millisecondsSinceEpoch,
      'duration_ms': durationMs,
    });

    return VaultItem(
      id: id,
      type: type,
      originalFilePath: originalFilePath,
      thumbnailBlob: thumbnailBlob,
      dateCreated: dateCreated,
      durationMs: durationMs,
    );
  }

  /// حذف عنصر من قاعدة البيانات (مش بيحذف الملف المشفّر نفسه من القرص).
  static Future<void> deleteItem(int id) async {
    final db = await _open();
    await db.delete('vault_items', where: 'id = ?', whereArgs: [id]);
  }

  /// قفل الاتصال بقاعدة البيانات (بينادى وقت الخروج من شاشة الخزنة).
  static Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _db = null;
  }
}

