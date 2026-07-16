import 'dart:ui';
import 'package:flutter/material.dart';

/// كل عناصر الشكل والستايل الخاصة بشاشة الكاميرا (CameraScreen) مجمعة هنا:
/// زرار التصوير، سلايدر الوضع (فيديو/صورة)، عداد وقت التسجيل، شاشة
/// "جاري التأكد من التشفير"، والزرار الدائري العام.
///
/// كل حاجة هنا widgets نقية (pure) - مالهاش أي state أو منطق عمل، بتاخد
/// بياناتها كـ parameters وترجع Widget بس. المنطق والتحكم لسه في
/// camera_screen.dart و camera_controller_manager.dart.
class CameraScreenStyle {
  CameraScreenStyle._();

  // ===== زرار التصوير الدائري (الحلقة + الشكل الداخلي) =====
  static const double ringOuterSize = 78;
  static const double ringStrokeWidth = 4;
  static const double innerSquareSize = 30; // حجم المربع وقت التسجيل
  static const double innerIdleSize = 62; // حجم الدايرة البيضا وقت السكون

  static Widget captureButton({
    required bool isRecording,
    required bool isRed,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: ringOuterSize,
        height: ringOuterSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // الحلقة الخارجية - ثابتة تمامًا، بتغير لونها بس (أبيض/أحمر)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: ringOuterSize,
              height: ringOuterSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isRed ? Colors.red : Colors.white,
                  width: ringStrokeWidth,
                ),
              ),
            ),
            // الشكل الداخلي: دايرة وقت السكون، مربع بزوايا مدورة وقت التسجيل
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              width: isRecording ? innerSquareSize : innerIdleSize,
              height: isRecording ? innerSquareSize : innerIdleSize,
              decoration: BoxDecoration(
                color: isRed ? Colors.red : Colors.white,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(
                  isRecording ? 10 : (innerIdleSize / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== سلايدر اختيار الوضع (فيديو / صورة) =====
  static Widget modeSlider({
    required PageController controller,
    required List<String> modeLabels,
    required int currentModeIndex,
    required ValueChanged<int> onPageChanged,
  }) {
    return SizedBox(
      height: 36,
      child: PageView.builder(
        controller: controller,
        itemCount: modeLabels.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          final bool selected = index == currentModeIndex;
          return Center(
            child: GestureDetector(
              onTap: () {
                controller.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
              child: Text(
                modeLabels[index],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: selected ? 16 : 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===== عداد وقت التسجيل: نقطة حمرا وميضة + الوقت (mm:ss) =====
  static Widget recordingTimer(String formattedDuration) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formattedDuration,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===== شاشة تحميل "جاري التأكد من سلامة الفيديو المشفر" =====
  static Widget verifyingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black87,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  "جاري التأكد من سلامة الفيديو المشفر...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "من فضلك متقفلش الكاميرا دلوقتي",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== زرار دائري عام (مستخدم لزرار الفلاتر/الإضافات) =====
  static Widget circularButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  // ===== بريفيو الكاميرا بنسبة 4:3 ثابتة (frame) =====
  static Widget framedPreview(CameraPreviewData data) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRect(
        child: data.previewSize == null
            ? data.preview
            : FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: data.previewSize!.height,
                  height: data.previewSize!.width,
                  child: data.preview,
                ),
              ),
      ),
    );
  }

  // ===== شريط إعدادات الجودة (bottom sheet) - الشكل فقط =====
  static Widget qualitySheetContainer({required Widget child}) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: child,
      ),
    );
  }

  static Widget sheetHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white30,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  static const sheetTitle = Text(
    "Camera Settings",
    style: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );
}

/// بيانات بسيطة بتتبعت لـ [CameraScreenStyle.framedPreview] بدل ما نبعت
/// الـ CameraController كامل لكلاس الستايل (فصل الاعتمادية عن منطق الكاميرا).
class CameraPreviewData {
  final Widget preview;
  final Size? previewSize;
  const CameraPreviewData({required this.preview, required this.previewSize});
}
