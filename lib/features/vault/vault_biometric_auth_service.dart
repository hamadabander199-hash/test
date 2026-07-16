import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final _auth = LocalAuthentication();

  /// تحقق من هوية المستخدم (PIN / Password / Biometric)
  static Future<bool> authenticate({required String reason}) async {
    try {
      debugPrint("🔐 بدء التحقق من الهوية...");
      final result = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // يمكن PIN أو Password أو FaceID
      );
      debugPrint("✅ نتيجة التحقق: $result");
      return result;
    } catch (e) {
      debugPrint("⚠️ خطأ أثناء التحقق: $e");
      return false;
    }
  }
}
