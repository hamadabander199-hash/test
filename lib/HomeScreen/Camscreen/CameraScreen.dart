import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'CameraControls.dart';
import 'mangecodecamera.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraControllerManager cameraManager;

  // وضع التصوير الحالي: صورة أو فيديو (زي السلايدر في كاميرا الموبايل)
  final List<String> _modeLabels = ['فيديو', 'صورة'];
  int _currentModeIndex = 1; // يبدأ على وضع "صورة"
  late final PageController _modePageController;

  @override
  void initState() {
    super.initState();
    _modePageController = PageController(
      viewportFraction: 0.32,
      initialPage: _currentModeIndex,
    );
    cameraManager = CameraControllerManager(
      onUpdate: () {
        setState(() {});
      },
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await cameraManager.initCameras();
    } catch (e) {
    }
  }

  @override
  void dispose() {
    cameraManager.dispose();
    _modePageController.dispose();
    super.dispose();
  }

  void openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Camera Settings",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              _buildSettingTile("Low Quality", ResolutionPreset.low),
              _buildSettingTile("Medium Quality", ResolutionPreset.medium),
              _buildSettingTile("High Quality (HD)", ResolutionPreset.high),
              _buildSettingTile("Very High Quality", ResolutionPreset.veryHigh),
              _buildSettingTile("Ultra High Quality", ResolutionPreset.ultraHigh),
              _buildSettingTile("Max Quality", ResolutionPreset.max),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingTile(String title, ResolutionPreset preset) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      trailing: cameraManager.controller != null &&
          cameraManager.controller!.value.isInitialized &&
          cameraManager.controller!.value.previewSize != null &&
          cameraManager.controller!.value.previewSize!.width == preset.index
          ? const Icon(Icons.check, color: Colors.green)
          : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white30),
      onTap: () async {
        await cameraManager.setCameraQuality(preset);
        Navigator.pop(context);
      },
    );
  }

  // بريفيو بنسبة 4:3 ثابتة (زي كاميرا الموبايل الأصلية) من غير أي تشويه أو تمطيط.
  // بيستخدم الأبعاد الحقيقية القادمة من الكاميرا (previewSize) عشان يملا المربع
  // بشكل صحيح ويقص الزيادة بس، بدل ما يمط الصورة أو يسيب حواف سودة.
  Widget _buildFramedPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;

    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRect(
        child: previewSize == null
            ? CameraPreview(controller)
            : FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            // previewSize بيرجع دايمًا بالمقاس الأفقي (landscape) من السنسور
            // فبنقلب العرض والارتفاع عشان يتظبطوا صح في الوضع الرأسي (portrait).
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  // سلايدر اختيار الوضع (فيديو / صورة) زي كاميرا الموبايل بالظبط - بيتسحب يمين وشمال
  Widget _buildModeSlider() {
    return SizedBox(
      height: 36,
      child: PageView.builder(
        controller: _modePageController,
        itemCount: _modeLabels.length,
        onPageChanged: (index) {
          setState(() => _currentModeIndex = index);
        },
        itemBuilder: (context, index) {
          final bool selected = index == _currentModeIndex;
          return Center(
            child: GestureDetector(
              onTap: () {
                _modePageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
              child: Text(
                _modeLabels[index],
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

  bool get _isVideoMode => _modeLabels[_currentModeIndex] == 'فيديو';

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // عداد وقت التسجيل: نقطة حمرا وميضة + الوقت (mm:ss)
  Widget _buildRecordingTimer() {
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
            _formatDuration(cameraManager.recordingDuration),
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

  // زرار التصوير الواحد - بيتصرف بالظبط زي كاميرا الآيفون:
  // الحلقة البيضا برا حجمها ثابت ومش بتتحرك خالص، وبس الدايرة/المربع اللي
  // جواها هو اللي بيتحول بحركة سلسة، وده اللي بيدي إحساس التحول الأصلي.
  static const double _ringOuterSize = 78;
  static const double _ringStrokeWidth = 4;
  static const double _innerSquareSize = 30; // حجم المربع وقت التسجيل
  static const double _innerIdleSize = 62;   // حجم الدايرة البيضا وقت السكون

  Widget _buildCaptureButton() {
    final bool isRecording = cameraManager.isRecording;
    final bool isRed = _isVideoMode || isRecording;
    return GestureDetector(
      onTap: () async {
        try {
          if (_isVideoMode) {
            await cameraManager.toggleVideoRecording();
          } else {
            await cameraManager.capture();
          }
        } catch (e) {
        }
      },
      child: SizedBox(
        width: _ringOuterSize,
        height: _ringOuterSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // الحلقة الخارجية - ثابتة تمامًا، بتغير لونها بس (أبيض/أحمر)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _ringOuterSize,
              height: _ringOuterSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isRed ? Colors.red : Colors.white,
                  width: _ringStrokeWidth,
                ),
              ),
            ),
            // الشكل الداخلي - تم تعديله هنا لحل المشكلة
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              width: isRecording ? _innerSquareSize : _innerIdleSize,
              height: isRecording ? _innerSquareSize : _innerIdleSize,
              decoration: BoxDecoration(
                color: isRed ? Colors.red : Colors.white,
                shape: BoxShape.rectangle, // دايمًا مستطيل عشان الـ Animation يشتغل صح
                borderRadius: BorderRadius.circular(
                  // إذا كان بيسجل: زوايا دائرية خفيفة (مربع مدور)
                  // إذا كان واقف: نصف القطر بيساوي نصف الحجم فيتحول لدائرة مثالية
                  isRecording ? 10 : (_innerIdleSize / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraManager.controller == null || !cameraManager.controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final controller = cameraManager.controller!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),

                // شريط الأيقونات العلوي (تبديل الكاميرا / فلاش / إعدادات)
                CameraControls(
                  controller: cameraManager.controller,
                  isFlashOn: cameraManager.flashOn,
                  onSwitchCamera: () async {
                    await cameraManager.switchCamera();
                  },
                  onFlashToggle: () async {
                    await cameraManager.toggleFlash();
                  },
                  onSettings: openSettings,
                ),

                const SizedBox(height: 8),

                // البريفيو بنسبة 4:3 ثابتة، زي كاميرا الموبايل الأصلية
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    _buildFramedPreview(controller),
                    if (cameraManager.isRecording)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildRecordingTimer(),
                      ),
                  ],
                ),

                // المساحة السودة تحت البريفيو، فيها أزرار التصوير
                // مبنية بـ Stack + Positioned بمواقع ثابتة (مش Row/Column) عشان
                // مفيش أي RenderFlex ممكن يظهر له overflow حتى لو حصل أي
                // تغيير مؤقت في القياسات لحظة بدء التسجيل
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: double.infinity,
                      height: 150,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // السلايدر: فيديو / صورة
                          Positioned(
                            top: 4,
                            left: 0,
                            right: 0,
                            height: 36,
                            child: _buildModeSlider(),
                          ),
                          // زرار التصوير في المنتصف
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Center(child: _buildCaptureButton()),
                          ),
                          // زرار الفلاتر/الإضافات على اليمين
                          Positioned(
                            bottom: 27,
                            right: 24,
                            child: _buildCircularButton(
                              icon: Icons.auto_awesome,
                              color: Colors.white24,
                              onTap: () {
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // شاشة تحميل بتظهر فوق كل حاجة وقت ما بنراجع سلامة الفيديو
          // المشفر النهائي بعد ما التسجيل يوقف - وبتمنع أي تفاعل مع
          // الشاشة لحد ما التحقق يخلص
          if (cameraManager.isVerifying) _buildVerifyingOverlay(),
        ],
      ),
    );
  }

  Widget _buildVerifyingOverlay() {
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
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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

  Widget _buildCircularButton({
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
}