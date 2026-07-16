import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraControls extends StatelessWidget {
  final CameraController? controller;
  final VoidCallback onSwitchCamera;
  final VoidCallback onFlashToggle;
  final VoidCallback onSettings;

  final bool isFlashOn;

  CameraControls({
    required this.controller,
    required this.onSwitchCamera,
    required this.onFlashToggle,
    required this.onSettings,
    this.isFlashOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // زر تبديل الكاميرا
          IconButton(
            icon: Icon(Icons.cameraswitch, color: Colors.white, size: 30),
            onPressed: onSwitchCamera,
          ),

          // زر فلاش
          IconButton(
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.yellowAccent,
              size: 30,
            ),
            onPressed: onFlashToggle,
          ),

          // زر الإعدادات
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white, size: 30),
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}