import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../theme/app_theme.dart';

/// قناة أمان مباشرة مع MainActivity.kt للتحكم في FLAG_SECURE (منع
/// screenshot/screen recording). عملناها MethodChannel بسيط بدل ما
/// نعتمد على مكتبة flutter_windowmanager الخارجية، لأنها مكتبة قديمة
/// مش متحدثة وبتكسر الـ Gradle build مع AGP الحديث (namespace غير
/// محدد في build.gradle بتاعها).
class _SecureFlagChannel {
  static const MethodChannel _channel = MethodChannel('camzone/security');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enableSecureFlag');
    } catch (_) {
      // منصة مش مدعومة (مثلاً أثناء التطوير على ديسكتوب) — نتجاهل.
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disableSecureFlag');
    } catch (_) {}
  }
}

/// بوابة أمان بتلف أي محتوى حساس (شاشة الخزنة):
/// - مصادقة بيومترية (بصمة/Face ID) إجبارية قبل عرض المحتوى.
/// - لو المستخدم رجع من الـ background وهو لسه فاتح الشاشة، بيتطلب
///   مصادقة تانية قبل ما يشوف المحتوى تاني.
/// - FLAG_SECURE على أندرويد طول ما الشاشة دي مفتوحة، يعني منع
///   screenshot / screen recording بالكامل (مش بلور، منع فعلي).
///
/// [builder] بيتنادى بس بعد نجاح المصادقة، ويتشال (يترجع الـ lock)
/// فور ما الشاشة تختفي من الخلفية أو المصادقة تفشل.
class VaultAuthGate extends StatefulWidget {
  final WidgetBuilder builder;

  const VaultAuthGate({super.key, required this.builder});

  @override
  State<VaultAuthGate> createState() => _VaultAuthGateState();
}

class _VaultAuthGateState extends State<VaultAuthGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _unlocked = false;
  bool _authInProgress = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableSecureFlag();
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableSecureFlag();
    super.dispose();
  }

  Future<void> _enableSecureFlag() async {
    await _SecureFlagChannel.enable();
  }

  Future<void> _disableSecureFlag() async {
    await _SecureFlagChannel.disable();
  }

  bool _needsReauthOnResume = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // لو الـ pause ده ناتج عن بروبمت المصادقة نفسه (شاشة PIN بتاعة
      // الجهاز أو بروبمت البصمة بتاخد الـ activity لحظة)، متعتبروش
      // "التطبيق راح الخلفية" — ده جزء طبيعي من نفس عملية المصادقة
      // الجارية، ومينفعش نقفل فور ما تنجح.
      if (!_authInProgress && _unlocked) {
        _needsReauthOnResume = true;
        setState(() => _unlocked = false);
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      // بنطلب مصادقة تانية بس لو فعلاً كان فيه pause حقيقي (رجوع من
      // الخلفية) قبل كده، مش كل resumed بييجي (زي اللي بيحصل مباشرة
      // بعد ما بروبمت المصادقة نفسه يقفل).
      if (_needsReauthOnResume && !_unlocked && !_authInProgress) {
        _needsReauthOnResume = false;
        _authenticate();
      }
    }
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    setState(() {
      _authInProgress = true;
      _errorMessage = null;
    });

    try {
      final canCheck = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();

      if (!canCheck) {
        setState(() {
          _errorMessage = 'الجهاز ده مش بيدعم بصمة/Face ID.';
          _authInProgress = false;
        });
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'افتح الخزنة ببصمتك أو Face ID',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;
      setState(() {
        _unlocked = didAuthenticate;
        _authInProgress = false;
        if (!didAuthenticate) {
          _errorMessage = 'فشلت المصادقة، حاول تاني.';
        }
      });
    } on LocalAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _authInProgress = false;
        _errorMessage = _friendlyAuthError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authInProgress = false;
        _errorMessage = 'حصل خطأ أثناء المصادقة: $e';
      });
    }
  }

  String _friendlyAuthError(LocalAuthException e) {
    switch (e.code) {
      case LocalAuthExceptionCode.userCanceled:
        return 'اتلغت المصادقة.';
      case LocalAuthExceptionCode.noBiometricHardware:
        return 'مفيش بصمة/Face ID مسجّلة — استخدم قفل شاشة الجهاز بدلًا منها.';
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return 'المحاولات وقفت مؤقتًا، جرّب تاني بعد شوية.';
      default:
      // بيغطي كمان uiUnavailable/notEnrolled وأي كود تاني غير متوقع —
      // بنسيب المستخدم يضغط "حاول تاني" ويستخدم قفل شاشة الجهاز
      // (PIN/Pattern/Password) كبديل للبصمة تلقائيًا.
        return 'فشلت المصادقة، حاول تاني.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return widget.builder(context);
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded,
                color: AppColors.primary, size: 48),
            const SizedBox(height: 16),
            if (_authInProgress)
              const CircularProgressIndicator(color: AppColors.primary)
            else ...[
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 8),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              TextButton(
                onPressed: _authenticate,
                child: const Text('حاول تاني'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}