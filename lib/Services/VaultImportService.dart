import 'dart:async';
import 'package:video_player/video_player.dart';

import '../HomeScreen/Vault/vault_item.dart';
import 'LoopbackVideoServer.dart';
import 'NativeCryptoService.dart';
import 'VaultDatabaseService.dart';
import 'VaultThumbnailService.dart';

/// بتنسّق عملية استيراد ملف `.enc` جديد جوه الخزنة:
/// 1. تتأكد إن الملف فعلاً امتداده .enc.
/// 2. تفك تشفيره **في الذاكرة بس** (عشان تعرف نوعه فعليًا: صورة ولا
///    فيديو) — الملف الأصلي المشفر ده هو اللي هيفضل محفوظ على القرص
///    (originalFilePath)، مش أي نسخة plaintext منه.
/// 3. تولّد ثامبنيل (حقيقي للصور، بلاسيهولدر للفيديو) وتحسب مدة الفيديو
///    لو النوع فيديو.
/// 4. تحفظ سجل جديد في قاعدة بيانات SQLCipher.
///
/// ملحوظة: البايتات المفكوكة بتتشال من الذاكرة فور الانتهاء من الخطوة —
/// مفيش أي نسخة plaintext بتتكتب على التخزين في أي وقت.
class VaultImportService {
  VaultImportService._();

  static const _imageMagicBytes = <List<int>>[
    [0xFF, 0xD8, 0xFF], // JPEG
    [0x89, 0x50, 0x4E, 0x47], // PNG
  ];

  /// بترجع الـ VaultItem اللي اتضاف، أو بترمي Exception لو الملف مش
  /// .enc صالح أو فشل فك تشفيره (مفتاح غلط / ملف تالف).
  static Future<VaultItem> importEncFile(String encFilePath) async {
    if (!encFilePath.toLowerCase().endsWith('.enc')) {
      throw Exception('الملف المختار مش ملف .enc');
    }

    final decryptedBytes =
        await NativeCryptoService.decryptToBytes(inputPath: encFilePath);

    final isPhoto = _looksLikeImage(decryptedBytes);

    if (isPhoto) {
      final thumb =
          await VaultThumbnailService.generatePhotoThumbnail(decryptedBytes);

      final item = VaultItem(
        originalFilePath: encFilePath,
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
      originalFilePath: encFilePath,
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
