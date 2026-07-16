import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../HomeScreen/Vault/vault_item.dart';
import 'LoopbackVideoServer.dart';
import 'NativeCryptoService.dart';
import 'VaultDatabaseService.dart';
import 'VaultThumbnailService.dart';

/// بتنسّق عملية استيراد ملف `.enc` جديد جوه الخزنة:
/// 1. تتأكد إن الملف فعلاً امتداده .enc.
/// 2. تنسخ الملف المشفّر (بايتات خام، من غير فك تشفير) لفولدر دائم اسمه
///    "PrivateSafe" جوه مساحة تخزين التطبيق - عشان المسار اللي بيرجعه
///    الفايل بيكر غالبًا بيكون مؤقت (cache/tmp) وبيتمسح من النظام في أي
///    وقت، فلو خزّنّا نفس المسار ده في قاعدة البيانات، السجل هيفضل
///    موجود بس الملف نفسه هيختفي فجأة.
/// 3. تفك تشفير النسخة الجديدة **في الذاكرة بس** (عشان تعرف نوعه فعليًا:
///    صورة ولا فيديو) — النسخة المشفّرة في PrivateSafe هي اللي هتفضل
///    محفوظة على القرص (originalFilePath)، مش أي نسخة plaintext منها.
/// 4. تولّد ثامبنيل (حقيقي للصور، بلاسيهولدر للفيديو) وتحسب مدة الفيديو
///    لو النوع فيديو.
/// 5. تحفظ سجل جديد في قاعدة بيانات SQLCipher.
///
/// ملحوظة: البايتات المفكوكة بتتشال من الذاكرة فور الانتهاء من الخطوة —
/// مفيش أي نسخة plaintext بتتكتب على التخزين في أي وقت.
class VaultImportService {
  VaultImportService._();

  static const _imageMagicBytes = <List<int>>[
    [0xFF, 0xD8, 0xFF], // JPEG
    [0x89, 0x50, 0x4E, 0x47], // PNG
  ];

  static const _privateSafeFolderName = 'PrivateSafe';

  /// بترجع المسار الكامل لفولدر PrivateSafe (بتنشئه لو مش موجود).
  static Future<Directory> _privateSafeDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final safeDir = Directory(p.join(docsDir.path, _privateSafeFolderName));
    if (!await safeDir.exists()) {
      await safeDir.create(recursive: true);
    }
    return safeDir;
  }

  /// بتنسخ الملف المختار لفولدر PrivateSafe باسم فريد (عشان أي تعارض
  /// أسماء بين ملفات مستوردة من أماكن مختلفة بنفس الاسم)، وترجع المسار
  /// الجديد الدائم.
  static Future<String> _copyToPrivateSafe(String sourcePath) async {
    final safeDir = await _privateSafeDir();
    final originalName = p.basenameWithoutExtension(sourcePath);
    final uniqueName =
        '${originalName}_${DateTime.now().microsecondsSinceEpoch}.enc';
    final destPath = p.join(safeDir.path, uniqueName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);
    return destPath;
  }

  /// بترجع الـ VaultItem اللي اتضاف، أو بترمي Exception لو الملف مش
  /// .enc صالح أو فشل فك تشفيره (مفتاح غلط / ملف تالف).
  static Future<VaultItem> importEncFile(String encFilePath) async {
    if (!encFilePath.toLowerCase().endsWith('.enc')) {
      throw Exception('الملف المختار مش ملف .enc');
    }

    // ننسخ الملف المشفّر (بايتات خام، من غير فك تشفير) لمكان دائم قبل
    // أي حاجة تانية - لو فشل فك التشفير بعد كده، الملف يفضل محفوظ في
    // PrivateSafe برضه (بنسيبه، المستخدم يقدر يمسحه يدويًا لو عايز).
    final persistedPath = await _copyToPrivateSafe(encFilePath);

    late final Uint8List decryptedBytes;
    try {
      decryptedBytes =
      await NativeCryptoService.decryptToBytes(inputPath: persistedPath);
    } catch (e) {
      // فشل فك التشفير - نمسح النسخة المنسوخة عشان منسيبش ملفات يتيمة
      // في PrivateSafe من غير سجل في قاعدة البيانات.
      final orphan = File(persistedPath);
      if (await orphan.exists()) {
        await orphan.delete();
      }
      rethrow;
    }

    final isPhoto = _looksLikeImage(decryptedBytes);

    if (isPhoto) {
      final thumb =
      await VaultThumbnailService.generatePhotoThumbnail(decryptedBytes);

      final item = VaultItem(
        originalFilePath: persistedPath,
        type: VaultItemType.photo,
        dateCreated: DateTime.now(),
        thumbnailBlob: thumb,
      );
      final id = await VaultDatabaseService.insert(item);
      return item.copyWith(id: id);
    }

    // فيديو: بنستخدم نفس سيرفر الـ loopback مؤقتًا بس عشان نقرا الـ
    // duration من video_player، وبعدين بنقفله فورًا — مفيش أي كتابة
    // على القرص في العملية دي.
    final server = LoopbackVideoServer(decryptedBytes);
    int? durationSeconds;
    try {
      final url = await server.start();
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      durationSeconds = controller.value.duration.inSeconds;
      await controller.dispose();
    } catch (_) {
      durationSeconds = null;
    } finally {
      await server.stop();
    }

    final thumb = await VaultThumbnailService.generateVideoPlaceholder();

    final item = VaultItem(
      originalFilePath: persistedPath,
      type: VaultItemType.video,
      dateCreated: DateTime.now(),
      durationSeconds: durationSeconds,
      thumbnailBlob: thumb,
    );
    final id = await VaultDatabaseService.insert(item);
    return item.copyWith(id: id);
  }

  static bool _looksLikeImage(List<int> bytes) {
    for (final magic in _imageMagicBytes) {
      if (bytes.length < magic.length) continue;
      var matches = true;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }
}