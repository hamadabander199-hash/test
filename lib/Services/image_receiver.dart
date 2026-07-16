import 'package:path_provider/path_provider.dart';
import 'NativeCryptoService.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ImageReceiver {

  static Future<String?> receiveImage(
      String path,
      String publicKeyPath,
      Function(double) onProgress
      ) async {

    try {

      Fluttertoast.showToast(
        msg: "⬇️ Starting encryption...",
        gravity: ToastGravity.BOTTOM,
      );

      final directory = await getApplicationDocumentsDirectory();

      // مجلد encrypted
      final encryptedDir = Directory("${directory.path}/encrypted");

      if (!await encryptedDir.exists()) {
        await encryptedDir.create(recursive: true);

        Fluttertoast.showToast(
          msg: "📂 Created encrypted folder",
          gravity: ToastGravity.BOTTOM,
        );
      }

      // تحديد نوع الملف
      String fileTypeSuffix;

      if (path.endsWith(".jpg") ||
          path.endsWith(".png") ||
          path.endsWith(".jpeg")) {

        fileTypeSuffix = "photo_enc";

      } else if (path.endsWith(".mp4") ||
          path.endsWith(".mov") ||
          path.endsWith(".avi")) {

        fileTypeSuffix = "vid_enc";

      } else {

        fileTypeSuffix = "file_enc";
      }

      // اسم الملف
      final now = DateTime.now();
      final formatted = DateFormat('yyyyMMddHHmmss').format(now);

      final newPath =
          "${encryptedDir.path}/enc_${fileTypeSuffix}_$formatted.enc";

      Fluttertoast.showToast(
        msg: "🛠️ Encrypting to:\n$newPath",
        gravity: ToastGravity.BOTTOM,
        toastLength: Toast.LENGTH_LONG,
      );

      bool success = false;
      String errorMessage = "";

      try {

        success = await NativeCryptoService.encrypt(
          inputPath: path,
          outputPath: newPath,
          publicKeyPath: publicKeyPath,
          onProgress: (progress) {

            onProgress(progress);
          },
        );

      } catch (e) {

        errorMessage = e.toString();
      }

      if (success) {

        Fluttertoast.showToast(
          msg: "✅ Encryption completed",
          gravity: ToastGravity.BOTTOM,
        );

        return newPath;

      } else {

        String message;

        if (errorMessage.isNotEmpty) {
          message = "❌ Encryption failed\n$errorMessage";
        } else {
          message = "❌ Encryption failed (unknown error)";
        }

        Fluttertoast.showToast(
          msg: message,
          gravity: ToastGravity.BOTTOM,
          toastLength: Toast.LENGTH_LONG,
        );

        return null;
      }

    } catch (e) {

      Fluttertoast.showToast(
        msg: "❌ Encryption error: $e",
        gravity: ToastGravity.BOTTOM,
        toastLength: Toast.LENGTH_LONG,
      );

      return null;
    }
  }
}