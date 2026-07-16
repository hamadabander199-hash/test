import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/home_shell.dart';
import 'login_screen_style.dart';

/// شاشة تسجيل الدخول. المنطق فقط (Firebase Auth، الـ state، التنقل)؛
/// كل الشكل والستايل (الكارت الزجاجي، الحقول، الزرار) موجود في
/// login_screen_style.dart.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passController = TextEditingController();

  bool isLoading = false;
  bool wrongCredentials = false;

  Future<void> login() async {
    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => Home()),
      );
    } on FirebaseAuthException {
      setState(() {
        isLoading = false;
        wrongCredentials = true;
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;

        setState(() {
          wrongCredentials = false;
        });
      });
    } catch (_) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: LoginScreenStyle.backgroundGradient,
        child: LoginScreenStyle.glassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoginScreenStyle.headerIcon,
              const SizedBox(height: 15),
              LoginScreenStyle.headerTitle,
              const SizedBox(height: 30),
              LoginScreenStyle.glassField(
                controller: emailController,
                hint: "Email",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 20),
              LoginScreenStyle.glassField(
                controller: passController,
                hint: "Password",
                obscure: true,
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 30),
              LoginScreenStyle.loginButton(
                isLoading: isLoading,
                wrongCredentials: wrongCredentials,
                onPressed: isLoading ? null : login,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
