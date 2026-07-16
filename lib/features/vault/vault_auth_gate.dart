import 'package:flutter/material.dart';

import 'vault_biometric_auth_service.dart';

/// بوابة بيومترية (بصمة/Face ID/PIN) بتحمي أي محتوى حساس (زي شاشة
/// الخزنة). المنطق:
///
/// - أول ما الـ widget يتبني، بيطلب مصادقة فورًا.
/// - لو التطبيق راح للخلفية (`AppLifecycleState.paused`) وبعدين رجع،
///   بيطلب مصادقة تاني، إلا لو إحنا في نص "intent خارجي متوقع" (زي
///   فتح file picker) اتحدد بـ [beginExternalIntent] / [endExternalIntent].
/// - لحد ما المصادقة تنجح، بيعرض شاشة قفل بدل المحتوى، مع زرار
///   لإعادة المحاولة.
class VaultAuthGate extends StatefulWidget {
  final WidgetBuilder builder;

  const VaultAuthGate({super.key, required this.builder});

  /// بيتنادى قبل ما نفتح واجهة خارجية متوقعة (زي file picker) عشان
  /// الـ lifecycle observer يتجاهل الـ pause/resume الناتجة عنها.
  static void beginExternalIntent() {
    _ignoreNextResume = true;
  }

  /// بيتنادى في finally بعد ما الواجهة الخارجية تقفل، عشان الفلاج
  /// ميفضلش عالق لو حصل exception غير متوقع.
  static void endExternalIntent() {
    _ignoreNextResume = false;
  }

  static bool _ignoreNextResume = false;

  @override
  State<VaultAuthGate> createState() => _VaultAuthGateState();
}

class _VaultAuthGateState extends State<VaultAuthGate>
    with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (VaultAuthGate._ignoreNextResume) {
        // التطبيق راح للخلفية بسبب واجهة خارجية متوقعة (file picker
        // مثلًا) - منقفلش الخزنة.
        return;
      }
      if (mounted && _isAuthenticated) {
        setState(() => _isAuthenticated = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (VaultAuthGate._ignoreNextResume) return;
      if (mounted && !_isAuthenticated) {
        _authenticate();
      }
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    final success = await AuthService.authenticate(
      reason: 'افتح الخزنة عشان تشوف الصور والفيديوهات المحمية',
    );

    if (!mounted) return;
    setState(() {
      _isAuthenticated = success;
      _isAuthenticating = false;
      _error = success ? null : 'فشلت المصادقة. جرّب تاني.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return widget.builder(context);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              const Text(
                'الخزنة محمية',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 24),
              _isAuthenticating
                  ? const CircularProgressIndicator(color: Colors.white70)
                  : ElevatedButton.icon(
                      onPressed: _authenticate,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('افتح الخزنة'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
