import 'dart:ui';
import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/material.dart';
import 'HomeScreen/Camscreen/CameraScreen.dart';
import 'HomeScreen/Filemange/file_manager_screen.dart';
import 'HomeScreen/Vault/vault_screen.dart';
import 'HomeScreen/AppSettings/app_settings_screen.dart';
import 'custom_nav_bar.dart'; // <-- استيراد الملف الجديد

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
        cupertinoItems: [
          CNTabBarItem(
            label: 'Camera',
            icon: CNSymbol('camera.fill'),
          ),
          CNTabBarItem(
            label: 'Files',
            icon: CNSymbol('folder.fill'),
          ),
          CNTabBarItem(
            label: 'Vault',
            icon: CNSymbol('lock.fill'),
          ),
          CNTabBarItem(
            label: 'Settings',
            icon: CNSymbol('gearshape.fill'),
          ),
        ],
        androidLiquidBar: _buildLiquidNavigationBar(),
      ),
    );
  }

  // ✅ نفس الكود بتاع الـ Liquid Glass اللي كتبناه قبل كده
  Widget _buildLiquidNavigationBar() {
    return SafeArea(
      child: Container(
        height: 70,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.25),
                    Colors.white.withOpacity(0.08),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    alignment: Alignment(
                      _indicatorX(currentIndex),
                      0,
                    ),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.15),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      icons.length,
                          (index) => _buildNavItem(icons[index], index),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// بتحسب موضع النقطة (indicator) على المحور الأفقي (-1 لأقصى الشمال،
  /// 1 لأقصى اليمين) بشكل يتماشى مع توزيع MainAxisAlignment.spaceAround
  /// لأي عدد تابات، مش بس حالة الاتنين تابات القديمة.
  double _indicatorX(int index) {
    final n = icons.length;
    if (n <= 1) return 0;
    return (2 * index + 1) / n - 1;
  }

  Widget _buildNavItem(IconData icon, int index) {
    bool isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale: isSelected ? 1.15 : 1.0,
            curve: Curves.easeOutBack,
            child: Icon(
              icon,
              size: 26,
              color: isSelected
                  ? Colors.white
                  : Colors.white.withOpacity(0.45),
            ),
          ),
        ),
      ),
    );
  }
}