import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/material.dart';
import '../camera/camera_screen.dart';
import '../file_manager/file_manager_screen.dart';
import '../vault/vault_screen.dart';
import '../app_settings/app_settings_screen.dart';
import '../../core/widgets/custom_nav_bar.dart';
import 'liquid_nav_bar.dart';

/// الحاوية الرئيسية للتطبيق بعد تسجيل الدخول: بتربط الـ 4 شاشات
/// الأساسية (كاميرا / ملفات / خزنة / إعدادات) بشريط تنقل سفلي، مع اختيار
/// شكل الشريط المناسب حسب المنصة (iOS تاب بار نيتيف، أندرويد Liquid
/// Glass) عن طريق buildNavBar في core/widgets/custom_nav_bar.dart.
class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int currentIndex = 0;

  final screens = [
    CameraScreen(),
    FileManagerScreen(),
    const VaultScreen(),
    const AppSettingsScreen(),
  ];

  final List<IconData> icons = [
    Icons.camera_alt_rounded,
    Icons.folder_rounded,
    Icons.lock_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: screens[currentIndex],
      bottomNavigationBar: buildNavBar(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
        cupertinoItems: const [
          CNTabBarItem(label: 'Camera', icon: CNSymbol('camera.fill')),
          CNTabBarItem(label: 'Files', icon: CNSymbol('folder.fill')),
          CNTabBarItem(label: 'Vault', icon: CNSymbol('lock.fill')),
          CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape.fill')),
        ],
        androidLiquidBar: LiquidNavBar(
          currentIndex: currentIndex,
          icons: icons,
          onTap: (index) => setState(() => currentIndex = index),
        ),
      ),
    );
  }
}
