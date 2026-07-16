import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// بتولّد ثامبنيل JPEG صغير **في الذاكرة بس** — مفيش أي كتابة لملف على
/// التخزين في أي لحظة من العملية دي. الناتج بايتات JPEG جاهزة تتحفظ مباشرة
/// في عمود `thumbnail_blob` جوه قاعدة بيانات SQLCipher.
class VaultThumbnailService {
  VaultThumbnailService._();

  static const int _targetSize = 300;

  /// ثامبنيل حقيقي للصورة: بياخد البايتات المفكوكة (Uint8List) بتاعة
  /// الصورة الأصلية، ويعمل resize لأصغر مقاس ويرجّع JPEG bytes.
  static Future<Uint8List> generatePhotoThumbnail(
      Uint8List decodedImageBytes) async {
    final decoded = img.decodeImage(decodedImageBytes);
    if (decoded == null) {
      return _generatePlaceholder(icon: Icons.image_rounded);
    }

    final resized = img.copyResizeCropSquare(decoded, size: _targetSize);
    final jpg = img.encodeJpg(resized, quality: 70);
    return Uint8List.fromList(jpg);
  }

  /// ثامبنيل الفيديو: مفيش استخراج فريم حقيقي (ده هيحتاج نسخة plaintext
  /// مؤقتة على القرص عن طريق مكتبات استخراج الفريمات المعتادة، وده ممنوع
  /// حسب سياسة الأمان). بدل كده بنرسم بلاسيهولدر (تدرّج + أيقونة تشغيل)
  /// عن طريق Canvas في الذاكرة، ونرجّعه كـ PNG bytes.
  static Future<Uint8List> generateVideoPlaceholder() async {
    return _generatePlaceholder(icon: Icons.play_circle_fill_rounded);
  }

  static Future<Uint8List> _generatePlaceholder({required IconData icon}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(_targetSize.toDouble(), _targetSize.toDouble());

    final gradient = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(size.width, size.height),
      [const Color(0xFF23252F), const Color(0xFF13141A)],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = gradient,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 90,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(_targetSize, _targetSize);
    final byteData =
    await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}