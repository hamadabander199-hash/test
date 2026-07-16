import 'dart:ui';
import 'package:flutter/material.dart';

/// كل عناصر الشكل والستايل الخاصة بشاشة تسجيل الدخول (Glassmorphism):
/// الخلفية المتدرجة، الكارت الزجاجي، حقول الإدخال، وزرار الدخول.
/// مفيش هنا أي منطق دخول (login) - ده كله في login_screen.dart.
class LoginScreenStyle {
  LoginScreenStyle._();

  static const backgroundGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color(0xff6C63FF),
        Color(0xff4A90E2),
        Color(0xff00C9A7),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// حقل إدخال بتأثير زجاجي (blur + شفافية)، مستخدم للإيميل والباسورد.
  static Widget glassField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    IconData? icon,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(.25),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: InputBorder.none,
              prefixIcon: Icon(icon, color: Colors.white70),
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white70),
              contentPadding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ),
      ),
    );
  }

  /// الكارت الزجاجي اللي بيلف محتوى الشاشة كله (اللوجو + الحقول + الزرار).
  static Widget glassCard({required Widget child}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.12),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withOpacity(.2),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  static const headerIcon = Icon(
    Icons.lock_outline,
    size: 70,
    color: Colors.white,
  );

  static const headerTitle = Text(
    "Welcome Back",
    style: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );

  /// زرار الدخول: بيتلوّن أحمر لو بيانات غلط، وبيعرض spinner وقت التحميل.
  static Widget loginButton({
    required bool isLoading,
    required bool wrongCredentials,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: wrongCredentials ? Colors.red : Colors.white,
          foregroundColor: wrongCredentials ? Colors.white : Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  wrongCredentials ? "Wrong Credentials" : "Login",
                  key: ValueKey(wrongCredentials),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }
}
