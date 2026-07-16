import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyService {
  static final _storage = FlutterSecureStorage();

  // 🔑 أسماء المفاتيح
  static const _keyName = 'private_pem';
  static const _publicKeyName = 'public_pem';

  // =========================
  // PRIVATE KEY (زي ما هو)
  // =========================

  /// حفظ المفتاح الخاص بشكل آمن
  static Future<void> save(String privateKey) async {
    await _storage.write(key: _keyName, value: privateKey);
  }

  /// التحقق من وجود المفتاح الخاص
  static Future<bool> hasKey() async {
    final value = await _storage.read(key: _keyName);
    return value != null && value.isNotEmpty;
  }

  /// حذف المفتاح الخاص
  static Future<void> delete() async {
    await _storage.delete(key: _keyName);
  }

  /// قراءة المفتاح الخاص
  static Future<String?> read() async {
    return await _storage.read(key: _keyName);
  }

  // =========================
  // PUBLIC KEY (مضاف صح)
  // =========================

  /// حفظ المفتاح العام
  static Future<void> savePublicKey(String publicKey) async {
    await _storage.write(key: _publicKeyName, value: publicKey);
  }

  /// التحقق من وجود المفتاح العام
  static Future<bool> hasPublicKey() async {
    final value = await _storage.read(key: _publicKeyName);
    return value != null && value.isNotEmpty;
  }

  /// قراءة المفتاح العام
  static Future<String?> readPublicKey() async {
    return await _storage.read(key: _publicKeyName);
  }

  /// حذف المفتاح العام
  static Future<void> deletePublicKey() async {
    await _storage.delete(key: _publicKeyName);
  }

  // =========================
  // حذف الكل (اختياري)
  // =========================
  static Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
