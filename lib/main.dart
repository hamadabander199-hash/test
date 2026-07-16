import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_config/firebase_options.dart'; // ✅ ملف الخيارات لكل منصة
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, // ✅ استخدام الخيارات حسب المنصة
    );
  } catch (e) {
    // لو Firebase فشل، يمكن التعامل مع الخطأ بطريقة مناسبة للإنتاج
    return; // إيقاف التطبيق إذا فشل Firebase
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthCheck(),
    );
  }
}

// يتحقق من تسجيل الدخول
class AuthCheck extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return LoginScreen();
    } else {
      return Home();
    }
  }
}
