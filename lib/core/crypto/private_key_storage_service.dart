import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// بيخزّن المفتاح الخاص (private key PEM) اللي المستخدم بيستورده يدويًا
/// من شاشة الإعدادات، بشكل آمن جوه [FlutterSecureStorage] (اللي بيتخزن
/// فعليًا في Android Keystore / iOS Keychain).
///
/// لو المستخدم حدد "passphrase" وقت الاستيراد، بنعمل طبقة تشفير إضافية
/// (AES-256-CBC) فوق الـ PEM قبل ما نحطه في الـ secure storage، عشان
/// حتى لو حد عنده وصول لملفات الـ Keystore بشكل غير طبيعي (جهاز
/// مكسور/rooted) يفضل محتاج الـ passphrase عشان يقرا المفتاح الفعلي.
/// لو الـ passphrase فاضية، بنخزن الـ PEM زي ما هو (الحماية بتبقى بس
/// من الـ OS-level secure storage، وده برضو مقبول لمعظم الاستخدامات).
class PrivateKeyStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyName = 'vault_private_key_pem_v1';
  static const _saltName = 'vault_private_key_salt_v1';
  static const _hasPassphraseFlag = 'vault_private_key_has_passphrase_v1';

  /// هل فيه مفتاح خاص متخزن حاليًا؟
  static Future<bool> hasPrivateKey() async {
    final value = await _storage.read(key: _keyName);
    return value != null && value.isNotEmpty;
  }

  /// حفظ المفتاح الخاص (نص PEM كامل). لو `passphrase` مش فاضية، بنشفّره
  /// بيها قبل التخزين.
  static Future<void> savePrivateKey(
    String pemContent, {
    String? passphrase,
  }) async {
    final normalized = pemContent.trim();
    if (!normalized.startsWith('-----BEGIN') ||
        !normalized.contains('-----END')) {
      throw const FormatException('الملف ده مش مفتاح PEM صالح.');
    }

    if (passphrase != null && passphrase.isNotEmpty) {
      final salt = _generateSalt();
      final key = _deriveKey(passphrase, salt);
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(normalized, iv: iv);

      // بنخزن iv:ciphertext مع بعض عشان نقدر نفك التشفير لاحقًا.
      final payload = '${iv.base64}:${encrypted.base64}';

      await _storage.write(key: _keyName, value: payload);
      await _storage.write(key: _saltName, value: base64Encode(salt));
      await _storage.write(key: _hasPassphraseFlag, value: 'true');
    } else {
      await _storage.write(key: _keyName, value: normalized);
      await _storage.delete(key: _saltName);
      await _storage.write(key: _hasPassphraseFlag, value: 'false');
    }
  }

  /// قراءة المفتاح الخاص كنص PEM. لو كان متخزن بـ passphrase، لازم
  /// تتبعت `passphrase` نفسها هنا عشان يتفك تشفيره، وإلا هيرجع null.
  static Future<String?> readPrivateKeyPem({String? passphrase}) async {
    final raw = await _storage.read(key: _keyName);
    if (raw == null || raw.isEmpty) return null;

    final hasPassphrase =
        (await _storage.read(key: _hasPassphraseFlag)) == 'true';

    if (!hasPassphrase) return raw;

    if (passphrase == null || passphrase.isEmpty) {
      // متخزن بباسفريز لكن محدش بعتها - منقدرش نفكه.
      return null;
    }

    final saltEncoded = await _storage.read(key: _saltName);
    if (saltEncoded == null) return null;

    try {
      final salt = base64Decode(saltEncoded);
      final key = _deriveKey(passphrase, salt);
      final parts = raw.split(':');
      if (parts.length != 2) return null;

      final iv = enc.IV.fromBase64(parts[0]);
      final encrypted = enc.Encrypted.fromBase64(parts[1]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (_) {
      // باسفريز غلط أو بيانات تالفة.
      return null;
    }
  }

  /// حذف المفتاح الخاص بشكل نهائي من التخزين الآمن.
  static Future<void> deletePrivateKey() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _saltName);
    await _storage.delete(key: _hasPassphraseFlag);
  }

  static Uint8List _generateSalt() {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rand.nextInt(256)));
  }

  static enc.Key _deriveKey(String passphrase, Uint8List salt) {
    // اشتقاق مفتاح 256-bit من الباسفريز + salt باستخدام PBKDF2 مبسّط
    // (تكرار HMAC-SHA256). كافي كطبقة حماية إضافية فوق secure storage.
    var digest = Hmac(sha256, salt).convert(utf8.encode(passphrase)).bytes;
    for (var i = 0; i < 10000; i++) {
      digest = Hmac(sha256, salt).convert(digest).bytes;
    }
    return enc.Key(Uint8List.fromList(digest));
  }
}
