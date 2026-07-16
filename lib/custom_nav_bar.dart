// custom_nav_bar.dart
import 'dart:io' show Platform;
import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget buildNavBar({
  required int currentIndex,
  required List<CNTabBarItem> cupertinoItems,
  required Function(int) onTap,
  required Widget androidLiquidBar,
}) {
  if (Platform.isIOS) {
    return CNTabBar(
      items: cupertinoItems,
      currentIndex: currentIndex,
      tint: CupertinoColors.activeBlue,
      height: 85,
      onTap: onTap,
    );
  }
  return androidLiquidBar;
}