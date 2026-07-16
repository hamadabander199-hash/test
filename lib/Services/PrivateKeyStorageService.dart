import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خدمة مسؤولة عن تخزين/قراءة/حذف المفتاح الخاص (Private Key) بأمان.
///
/// بتستخدم flutter_secure_storage اللي بتخزن القيمة فعليًا في:
/// - iOS: Keychain
/// - Android: Keystore-backed EncryptedSharedPreferences
///
/// ملحوظة أمان: مفيش أي method بترجع المفتاح للـ UI مباشرة عشان يتعرض
/// على الشاشة تاني بعد الحفظ. القراءة الوحيدة المتاحة (readPrivateKeyPem)
/// مخصصة لمنطق فك التشفير الداخلي (اللي هيتبني في خطوة لاحقة)، مش للعرض.
class PrivateKeyStorageService {
  PrivateKeyStorageService._();

  static const _storageKey = 'camzone_private_key_pem';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// بيحفظ محتوى المفتاح الخاص (نص PEM) في الـ Keychain/Keystore.
  /// بيستبدل أي مفتاح قديم موجود تلقائيًا.
  static Future<void> savePrivateKey(String pemContent) async {
    await _storage.write(key: _storageKey, value: pemContent);
  }

  /// بيرجع true لو فيه مفتاح مخزّن حاليًا، من غير ما يرجّع محتواه.
  static Future<bool> hasPrivateKey() async {
    return _storage.containsKey(key: _storageKey);
  }

  /// بيمسح المفتاح المخزّن نهائيًا.
  static Future<void> deletePrivateKey() async {
    await _storage.delete(key: _storageKey);
  }

  /// قراءة المفتاح الفعلية — لمنطق فك التشفير الداخلي بس (NativeCryptoService
  /// أو StreamingVideoEncryptor لاحقًا)، مينفعش تتستخدم لعرض المفتاح في الـ UI.
  static Future<String?> readPrivateKeyPem() async {
    return _storage.read(key: _storageKey);
  }
}
