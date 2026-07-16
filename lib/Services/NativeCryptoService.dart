import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'PrivateKeyStorageService.dart';

class NativeCryptoService {

  static const MethodChannel _channel =
  MethodChannel("camzone/encryption");

  static bool _progressHandlerRegistered = false;

  static Future<bool> encrypt({
    required String inputPath,
    required String outputPath,
    required String publicKeyPath,
    required Function(double) onProgress,
  }) async {

    // تسجيل progress handler مرة واحدة فقط
    if (!_progressHandlerRegistered) {

      _channel.setMethodCallHandler((call) async {

        if (call.method == "onProgress") {

          final progress = (call.arguments as num).toDouble();

          onProgress(progress);
        }

        return null;
      });

      _progressHandlerRegistered = true;
    }

    try {

      final result = await _channel.invokeMethod(
        "encryptFileNative",
        {
          "inputPath": inputPath,
          "outputPath": outputPath,
          "publicKeyPath": publicKeyPath,
        },
      );

      if (result == true) {
        return true;
      }

      throw Exception("Native encryption returned false");

    } on PlatformException catch (e) {

      throw Exception(
          "Native encryption failed: ${e.message ?? ''} ${e.details ?? ''}");

    } catch (e) {

      throw Exception("Native encryption error: $e");
    }
  }

  /// بيفك تشفير ملف ENCv1 كامل (صورة، أو فيديو صغير) في الذاكرة، ويرجّع
  /// البايتات نفسها (مفيش أي كتابة على القرص أبدًا). بيقرا المفتاح الخاص
  /// من التخزين الآمن (Keychain/Keystore) عن طريق PrivateKeyStorageService.
  ///
  /// بترمي Exception لو مفيش مفتاح خاص محفوظ، أو لو فك التشفير فشل (ملف
  /// تالف / متلاعب فيه / أو مفتاح غلط).
  static Future<Uint8List> decryptToBytes({
    required String inputPath,
  }) async {

    final privateKeyPem = await PrivateKeyStorageService.readPrivateKeyPem();

    if (privateKeyPem == null) {
      throw Exception(
          "لا يوجد مفتاح خاص محفوظ. من فضلك استورد المفتاح من شاشة الإعدادات أولًا.");
    }

    try {

      final result = await _channel.invokeMethod(
        "decryptFileToBytes",
        {
          "inputPath": inputPath,
          "privateKeyPem": privateKeyPem,
        },
      );

      if (result is Uint8List) {
        return result;
      }

      if (result is List<int>) {
        return Uint8List.fromList(result);
      }

      throw Exception("Native decryption returned an unexpected type");

    } on PlatformException catch (e) {

      throw Exception(
          "Native decryption failed: ${e.message ?? ''} ${e.details ?? ''}");

    } catch (e) {

      throw Exception("Native decryption error: $e");
    }
  }
}