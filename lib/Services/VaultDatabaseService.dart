import 'dart:io';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../HomeScreen/Vault/vault_item.dart';
import 'VaultKeyService.dart';

/// طبقة الوصول لقاعدة بيانات الخزنة — قاعدة بيانات واحدة مشفّرة بالكامل
/// بـ SQLCipher (مش SQLite عادي)، الـ passphrase بتاعها مشتق من نفس مفتاح
/// الـ Keychain/Keystore عن طريق [VaultKeyService].
///
/// ملحوظة أمان: مفيش أي ثامبنيل بيتحفظ كملف صورة منفصل على التخزين —
/// كل حاجة جوه العمود `thumbnail_blob` بس، جوه قاعدة البيانات المشفّرة دي.
class VaultDatabaseService {
  VaultDatabaseService._();

  static Database? _db;
  static const _dbFileName = 'camzone_vault.sqlcipher.db';
  static const table = 'vault_items';

  /// بيفتح (أو ينشئ) قاعدة البيانات بالـ passphrase المشتق من المفتاح
  /// الخاص. بيرمي Exception لو مفيش مفتاح خاص محفوظ أصلًا — الشاشة اللي
  /// بتنادي الميثود دي المفروض تتأكد إن فيه مفتاح قبل ما توصل هنا.
  static Future<Database> _open() async {
    if (_db != null) return _db!;

    final passphrase = await VaultKeyService.deriveDatabasePassphrase();
    if (passphrase == null) {
      throw Exception(
          'لا يوجد مفتاح خاص محفوظ. من فضلك استورد المفتاح من شاشة الإعدادات أولًا.');
    }

    final docsDir = await getApplicationDocumentsDirectory();

    // تأكيد إن الفولدر نفسه موجود فعلًا قبل محاولة فتح/إنشاء الملف جواه —
    // بعض الأجهزة/الحالات النادرة بترجع مسار الـ docs من غير ما تضمن إنه
    // اتعمله create فعليًا، وده كان بيسبب DatabaseException(open_failed).
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }

    final dbPath = p.join(docsDir.path, _dbFileName);

    try {
      _db = await _openCipherDb(dbPath, passphrase);
    } catch (e) {
      // لو فتح قاعدة البيانات فشل (open_failed) - يعني الملف الموجود
      // تالف/معطوب بشكل مايتفتحش خالص، أو مش متوافق مع الإصدار الحالي.
      // بدل ما نسيب المستخدم عالق على طول برسالة open_failed، بنمسح
      // الملف التالف ونجرب ننشئ واحد جديد نظيف.
      //
      // ملحوظة: ده معناه فقدان بيانات الخزنة القديمة، لكن لو الملف كان
      // فعلًا مش قابل للفتح فهو مش قابل للاسترجاع أصلًا في الحالة دي.
      final badFile = File(dbPath);
      if (await badFile.exists()) {
        try {
          await badFile.delete();
        } catch (_) {
          // لو فشل المسح نفسه (نادر جدًا)، نسيب الاستثناء الأصلي يتفرقع
          // بدل ما نخبي المشكلة.
          rethrow;
        }
      }

      _db = await _openCipherDb(dbPath, passphrase);
    }

    return _db!;
  }

  static Future<Database> _openCipherDb(
      String dbPath, String passphrase) async {
    return openDatabase(
      dbPath,
      password: passphrase,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            original_file_path TEXT NOT NULL,
            type TEXT NOT NULL,
            date_created INTEGER NOT NULL,
            duration INTEGER,
            thumbnail_blob BLOB NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_vault_date ON $table (date_created DESC)');
      },
    );
  }

  /// بتقفل الاتصال بقاعدة البيانات — تتنادى وقت قفل الخزنة (لوك/خروج من
  /// الشاشة) عشان الملف المشفر ميفضلش مفتوح من غير داعي.
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<int> insert(VaultItem item) async {
    final db = await _open();
    return db.insert(table, item.toMap());
  }

  static Future<void> deleteById(int id) async {
    final db = await _open();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// بتجيب صفحة واحدة بس من الصفوف (LIMIT/OFFSET)، مرتبة من الأحدث
  /// للأقدم — بتتنادى من GridView.builder حسب الخلايا الظاهرة فعليًا،
  /// مش كل الصفوف مرة واحدة.
  static Future<List<VaultItem>> fetchPage({
    required int limit,
    required int offset,
  }) async {
    final db = await _open();
    final rows = await db.query(
      table,
      orderBy: 'date_created DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((row) => VaultItem.fromMap(row)).toList();
  }

  static Future<int> count() async {
    final db = await _open();
    final result =
    await db.rawQuery('SELECT COUNT(*) as c FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}