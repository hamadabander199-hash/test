import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'PrivateKeyStorageService.dart';

/// بتشتق passphrase ثابت لقاعدة بيانات SQLCipher من نفس المفتاح
/// المخزّن بأمان في iOS Keychain / Android Keystore عن طريق
/// [PrivateKeyStorageService] — مفيش أي مفتاح تاني بيتخزن في مكان جديد.
///
/// الاشتقاق: SHA-256(PEM content) → hex string (64 حرف) بيُستخدم كـ
/// passphrase لفتح/إنشاء قاعدة بيانات الخزنة. بما إن الـ PEM نفسه محفوظ
/// بأمان، فالـ passphrase المشتق منه آمن بنفس القدر ومش محتاج تخزين منفصل.
class VaultKeyService {
  VaultKeyService._();

  /// بيرجع الـ passphrase المشتق، أو null لو مفيش مفتاح خاص محفوظ أصلًا
  /// (يعني المستخدم لسه ما استوردش المفتاح من شاشة الإعدادات).
  static Future<String?> deriveDatabasePassphrase() async {
    final pem = await PrivateKeyStorageService.readPrivateKeyPem();
    if (pem == null || pem.isEmpty) return null;

    final digest = sha256.convert(utf8.encode('camzone_vault_db::$pem'));
    return digest.toString();
  }
}
