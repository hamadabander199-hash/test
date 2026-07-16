import 'package:flutter/material.dart';

/// ألوان التطبيق الأساسية.
/// ملحوظة: القيم دي تقريبية بناءً على استخدامها في الكود (SettingsScreen)،
/// عدّلها بما يتناسب مع هوية التطبيق البصرية عندك.
class AppColors {
  static const Color primary = Color(0xFF3D7BFF);
  static const Color success = Color(0xFF2ECC71);

  static const Color surface = Color(0xFF1C1E26);
  static const Color surfaceElevated = Color(0xFF23252F);

  static const Color border = Color(0xFF33353F);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB5B8C2);
  static const Color textMuted = Color(0xFF7D808C);
}

/// قيم الاستدارة (border radius) المستخدمة في التطبيق.
class AppRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
}