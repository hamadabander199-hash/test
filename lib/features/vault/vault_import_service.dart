import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'vault_item.dart';
import '../../core/crypto/native_crypto_service.dart';
import 'vault_database_service.dart';

/// بيستورد ملف `.enc` (سواء جاي من مجلد `encrypted/` بتاع الكاميرا، أو
/// من أي مكان تاني اختاره المستخدم عن طريق file picker) للخزنة:
///
/// 1. بينسخ الملف المشفّر لمجلد دائم مخصص للخزنة (`vault/`) لو مش
///    موجود فيه أصلًا، عشان الخزنة متعتمدش على ملف ممكن يتحذف من مكان
///    تاني في التطبيق.
/// 2. بيفك تشفيره *مؤقتًا* في الذاكرة/على القرص عشان بس يولّد ثامبنيل
///    صغير ويحدد نوع ومدة المحتوى، وبعدين يمسح أي نسخة واضحة فورًا.
/// 3. بيضيف صف جديد في [VaultDatabaseService].
class VaultImportService {
  static const _vaultDirName = 'vault';

  static Future<VaultItem> importEncFile(String pickedPath) async {
    final permanentPath = await _ensureInVaultStorage(pickedPath);

    // فك تشفير مؤقت عشان بس نقدر نولّد ثامبنيل ونعرف النوع/المدة.
    final tempDecrypted = await NativeCryptoService.decryptToTempFile(
      inputPath: permanentPath,
      suggestedExtension: 'tmp',
    );

    try {
      final isVideo = _looksLikeVideo(pickedPath, tempDecrypted);

      if (isVideo) {
        return _importAsVideo(
          permanentPath: permanentPath,
          decryptedFile: tempDecrypted,
        );
      } else {
        return _importAsPhoto(
          permanentPath: permanentPath,
          decryptedFile: tempDecrypted,
        );
      }
    } finally {
      await tempDecrypted.delete().catchError((_) => tempDecrypted);
    }
  }

  static Future<VaultItem> _importAsPhoto({
    required String permanentPath,
    required File decryptedFile,
  }) async {
    final bytes = await decryptedFile.readAsBytes();
    final thumbnail = _buildImageThumbnail(bytes);

    return VaultDatabaseService.insertItem(
      type: VaultItemType.photo,
      originalFilePath: permanentPath,
      thumbnailBlob: thumbnail,
      dateCreated: DateTime.now(),
    );
  }

  static Future<VaultItem> _importAsVideo({
    required String permanentPath,
    required File decryptedFile,
  }) async {
    Uint8List thumbnail;
    try {
      final thumbBytes = await VideoThumbnail.thumbnailData(
        video: decryptedFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 70,
      );
      thumbnail = thumbBytes ?? _placeholderThumbnail();
    } catch (_) {
      thumbnail = _placeholderThumbnail();
    }

    var durationMs = 0;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(decryptedFile);
      await controller.initialize();
      durationMs = controller.value.duration.inMilliseconds;
    } catch (_) {
      durationMs = 0;
    } finally {
      await controller?.dispose();
    }

    return VaultDatabaseService.insertItem(
      type: VaultItemType.video,
      originalFilePath: permanentPath,
      thumbnailBlob: thumbnail,
      dateCreated: DateTime.now(),
      durationMs: durationMs,
    );
  }

  /// بينسخ ملف الـ .enc لمجلد الخزنة الدائم لو مش موجود فيه أصلًا،
  /// وبيرجّع المسار الدائم الجديد. لو الملف أصلًا جوه مجلد الخزنة
  /// (مثلًا اتحاول استيراده تاني)، بيرجّع نفس المسار من غير نسخ.
  static Future<String> _ensureInVaultStorage(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, _vaultDirName));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    if (p.isWithin(vaultDir.path, sourcePath)) {
      return sourcePath;
    }

    final baseName = p.basenameWithoutExtension(sourcePath);
    final ext = p.extension(sourcePath);
    final uniqueName =
        '${baseName}_${DateTime.now().microsecondsSinceEpoch}$ext';
    final destPath = p.join(vaultDir.path, uniqueName);

    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static bool _looksLikeVideo(String pickedPath, File decryptedFile) {
    final name = p.basename(pickedPath).toLowerCase();
    if (name.contains('vid_enc')) return true;
    if (name.contains('photo_enc')) return false;

    // fallback: نحاول نقرأ الـ magic bytes بتاعة الملف المفكوك عشان
    // نعرف نوعه لو الاسم مش بيديني إشارة واضحة.
    try {
      final bytes = decryptedFile.readAsBytesSync();
      if (bytes.length > 12) {
        // ftyp box هي علامة كلاسيكية لملفات mp4/mov.
        final header = String.fromCharCodes(bytes.sublist(4, 8));
        if (header == 'ftyp') return true;
      }
    } catch (_) {}
    return false;
  }

  static Uint8List _buildImageThumbnail(Uint8List originalBytes) {
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return _placeholderThumbnail();
      final resized = img.copyResize(decoded, width: 400);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    } catch (_) {
      return _placeholderThumbnail();
    }
  }

  static Uint8List _placeholderThumbnail() {
    // مربع رمادي 1x1 كـ JPEG بسيط لو فشل توليد ثامبنيل حقيقي - أفضل من
    // تفشيل الاستيراد بالكامل بسبب مشكلة في عرض الثامبنيل بس.
    final placeholder = img.Image(width: 1, height: 1);
    img.fill(placeholder, color: img.ColorRgb8(60, 60, 60));
    return Uint8List.fromList(img.encodeJpg(placeholder));
  }
}
