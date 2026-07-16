import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'private_key_storage_service.dart';

class NativeCryptoService {
  // 🔹 iOS MethodChannel
  static const MethodChannel _iosChannel = MethodChannel('my_crypto_native');

  // 🔹 Android MethodChannels
  static const MethodChannel _androidEncryptChannel =
      MethodChannel('native.encrypt');
  static const MethodChannel _androidDecryptChannel =
      MethodChannel('native.decrypt');

  /// 🔐 تشفير. `onProgress` هنا اختياري وبيتنادى بـ 0.0 قبل ما نبدأ و
  /// 1.0 بعد ما نخلص - القناة الـ native الحالية (C++) بتشتغل بشكل
  /// مزامن (synchronous) على ملف واحد فمفيش تقدّم حقيقي فعلي وسط
  /// العملية نقدر نبلّغه بيه، لكن الـ callback موجود عشان الواجهات
  /// (EncryptProgressDialog) تقدر تعرض spinner/progress bar بسيط.
  static Future<bool> encrypt({
    required String inputPath,
    required String outputPath,
    required String publicKeyPath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);
    try {
      final bool result;
      if (Platform.isIOS) {
        result = await _iosChannel.invokeMethod<bool>('encryptFile', {
              'inputPath': inputPath,
              'outputPath': outputPath,
              'publicKeyPath': publicKeyPath,
            }) ??
            false;
      } else if (Platform.isAndroid) {
        result = await _androidEncryptChannel.invokeMethod<bool>(
              'encrypt',
              {
                'inputPath': inputPath,
                'outputPath': outputPath,
                'publicKeyPath': publicKeyPath,
              },
            ) ??
            false;
      } else {
        throw UnsupportedError('Encrypt is not supported on this platform');
      }
      onProgress?.call(1.0);
      return result;
    } on PlatformException catch (e) {
      print('❌ Encrypt failed on ${Platform.operatingSystem}');
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      print('Details: ${e.details}');
      onProgress?.call(1.0);
      return false;
    }
  }

  /// 🔓 فك التشفير من ملف مشفّر لملف واضح على القرص (مسارات جاهزة).
  static Future<bool> decrypt({
    required String inputPath,
    required String outputPath,
    required String privateKeyPath,
  }) async {
    try {
      if (Platform.isIOS) {
        final bool? result =
            await _iosChannel.invokeMethod<bool>('decryptFile', {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'privateKeyPath': privateKeyPath,
        });
        return result ?? false;
      } else if (Platform.isAndroid) {
        final bool? result = await _androidDecryptChannel.invokeMethod<bool>(
          'decrypt',
          {
            'inputPath': inputPath,
            'outputPath': outputPath,
            'privateKeyPath': privateKeyPath,
          },
        );
        return result ?? false;
      } else {
        throw UnsupportedError('Decrypt is not supported on this platform');
      }
    } on PlatformException catch (e) {
      print('❌ Decrypt failed on ${Platform.operatingSystem}');
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      print('Details: ${e.details}');
      return false;
    }
  }

  /// بيفك تشفير ملف `.enc` مباشرة لـ bytes في الذاكرة (مفيد لعرض صورة
  /// من غير ما نسيب أي نسخة واضحة (plaintext) دايمة على القرص).
  ///
  /// بيقرا المفتاح الخاص من [PrivateKeyStorageService]، يكتبه لملف
  /// مؤقت (الـ native code محتاج مسار ملف مش نص)، يفك التشفير لملف
  /// مؤقت تاني، يقرا البايتات، وبعدين يمسح الملفين المؤقتين فورًا.
  static Future<Uint8List> decryptToBytes({
    required String inputPath,
    String? privateKeyPassphrase,
  }) async {
    final tempFile = await decryptToTempFile(
      inputPath: inputPath,
      privateKeyPassphrase: privateKeyPassphrase,
      suggestedExtension: 'dec',
    );
    try {
      return await tempFile.readAsBytes();
    } finally {
      await tempFile.delete().catchError((_) => tempFile);
    }
  }

  /// بيفك تشفير ملف `.enc` لملف مؤقت في مجلد الـ cache، وبيرجّع الملف
  /// نفسه. المسؤولية عن مسح الملف ده (بعد الاستخدام) بتقع على المتصل،
  /// لأن بعض الاستخدامات (زي تشغيل فيديو) محتاجة الملف يفضل موجود
  /// لفترة أطول من مجرد قراءة bytes.
  static Future<File> decryptToTempFile({
    required String inputPath,
    String? privateKeyPassphrase,
    String suggestedExtension = 'dec',
  }) async {
    final privateKeyPem = await PrivateKeyStorageService.readPrivateKeyPem(
      passphrase: privateKeyPassphrase,
    );
    if (privateKeyPem == null || privateKeyPem.isEmpty) {
      throw StateError(
        'لا يوجد مفتاح خاص متاح لفك التشفير. استورد المفتاح من شاشة الإعدادات.',
      );
    }

    final cacheDir = await getTemporaryDirectory();
    final rand = Random.secure().nextInt(1 << 32);
    final keyFilePath = '${cacheDir.path}/tmp_priv_$rand.pem';
    final outputPath =
        '${cacheDir.path}/tmp_dec_$rand.$suggestedExtension';

    final keyFile = File(keyFilePath);
    await keyFile.writeAsString(privateKeyPem, flush: true);

    try {
      final success = await decrypt(
        inputPath: inputPath,
        outputPath: outputPath,
        privateKeyPath: keyFilePath,
      );

      if (!success) {
        throw StateError('فشل فك تشفير الملف.');
      }

      return File(outputPath);
    } finally {
      // بنمسح ملف المفتاح المؤقت فورًا في كل الحالات (نجاح أو فشل).
      await keyFile.delete().catchError((_) => keyFile);
    }
  }

  /// بيتحقق إن مفتاح خاص معين (PEM نص) بيطابق مفتاح عام معين، عن طريق
  /// اختبار عملي: تشفير ملف صغير عشوائي بالمفتاح العام، وفك تشفيره
  /// بالمفتاح الخاص، والتأكد إن الناتج مطابق للأصل.
  static Future<bool> verifyPrivateKeyMatchesPublicKey({
    required String privateKeyPem,
    required String publicKeyPath,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final rand = Random.secure().nextInt(1 << 32);
    final privateKeyFile = File('${cacheDir.path}/tmp_verify_priv_$rand.pem');
    final plainFile = File('${cacheDir.path}/tmp_verify_plain_$rand.bin');
    final encFile = File('${cacheDir.path}/tmp_verify_enc_$rand.enc');
    final decFile = File('${cacheDir.path}/tmp_verify_dec_$rand.bin');

    try {
      final testBytes = Uint8List.fromList(
        List<int>.generate(64, (_) => Random.secure().nextInt(256)),
      );

      await privateKeyFile.writeAsString(privateKeyPem, flush: true);
      await plainFile.writeAsBytes(testBytes, flush: true);

      final encrypted = await encrypt(
        inputPath: plainFile.path,
        outputPath: encFile.path,
        publicKeyPath: publicKeyPath,
      );
      if (!encrypted) return false;

      final decrypted = await decrypt(
        inputPath: encFile.path,
        outputPath: decFile.path,
        privateKeyPath: privateKeyFile.path,
      );
      if (!decrypted) return false;

      final resultBytes = await decFile.readAsBytes();
      if (resultBytes.length != testBytes.length) return false;
      for (var i = 0; i < testBytes.length; i++) {
        if (resultBytes[i] != testBytes[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      for (final f in [privateKeyFile, plainFile, encFile, decFile]) {
        await f.delete().catchError((_) => f);
      }
    }
  }
}
