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

  /// بتنضّف نص PEM من أي تشوهات ممكن تحصل وقت النسخ/القراءة من ملف
  /// (BOM، CRLF بدل LF، مسافات في الآخر أو الأول، سطور فاضية زيادة،
  /// أو نص زيادة قبل/بعد الـ block نفسه) من غير ما تلمس محتوى المفتاح
  /// أو تشيل سطور BEGIN/END الأساسية.
  ///
  /// بترجع null لو النص مش شكله PEM صالح أصلًا (مفيش BEGIN/END متطابقين).
  static String? normalizePem(String raw) {
    // شيل أي BOM في الأول لو موجود.
    var text = raw.replaceFirst('\uFEFF', '');

    // وحّد كل أنواع نهايات السطر (CRLF / CR) لـ LF عادي.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // دور على أول block كامل BEGIN...END (بيدعم أي نوع مفتاح: RSA
    // PRIVATE KEY, PRIVATE KEY, EC PRIVATE KEY... إلخ) وتجاهل أي نص
    // زيادة قبله أو بعده (تعليقات، أسطر فاضية، أي حاجة لصقت بالغلط).
    final match = RegExp(
      r'-----BEGIN ([A-Z0-9 ]+?)-----([\s\S]*?)-----END \1-----',
    ).firstMatch(text);

    if (match == null) return null;

    final label = match.group(1)!.trim();
    final body = match.group(2)!;

    // نضّف سطور الـ base64 بتاعة الجسم: امسح أي مسافات بيضاء زيادة في
    // أول/آخر كل سطر، وامسح السطور الفاضية تمامًا، من غير ما نغيّر
    // ترتيب أو محتوى الأحرف نفسها.
    final cleanedLines = body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (cleanedLines.isEmpty) return null;

    final rebuilt = StringBuffer()
      ..writeln('-----BEGIN $label-----')
      ..writeln(cleanedLines.join('\n'))
      ..writeln('-----END $label-----');

    return rebuilt.toString().trim();
  }

  /// بيحفظ محتوى المفتاح الخاص (نص PEM) في الـ Keychain/Keystore، بعد
  /// تطبيع تنسيقه أولًا (شوف [normalizePem]) عشان أي فروقات شكلية في
  /// الملف الأصلي (CRLF، مسافات، BOM) متأثرش على فك التشفير بعدين.
  ///
  /// بترمي [FormatException] لو النص المُدخل مش شكله PEM صالح أصلًا.
  static Future<void> savePrivateKey(String pemContent) async {
    final normalized = normalizePem(pemContent);
    if (normalized == null) {
      throw const FormatException(
          'محتوى المفتاح مش شكله PEM صالح (لازم يحتوي على -----BEGIN...----- '
              'و -----END...----- متطابقين).');
    }
    await _storage.write(key: _storageKey, value: normalized);
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
  ///
  /// بتطبّع القيمة تاني قبل ما ترجّعها (خط دفاع تاني بعد الحفظ، تحسبًا
  /// لأي قيمة قديمة اتخزنت قبل إضافة التطبيع في [savePrivateKey]).
  static Future<String?> readPrivateKeyPem() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return null;
    return normalizePem(raw) ?? raw;
  }
}