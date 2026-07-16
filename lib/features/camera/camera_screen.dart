import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'camera_controls.dart';
import 'camera_controller_manager.dart';
import 'camera_screen_style.dart';

/// شاشة الكاميرا الرئيسية. مسؤولياتها: إدارة الـ state (وضع فيديو/صورة،
/// فتح شاشة الإعدادات) وتركيب الشاشة من العناصر الجاهزة اللي في
/// [CameraScreenStyle]. كل الشكل والستايل (زرار التصوير، السلايدر،
/// العداد...) موجود في camera_screen_style.dart، وكل منطق الكاميرا نفسها
/// (تشغيل، تسجيل، تشفير) موجود في camera_controller_manager.dart.
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
    } catch (e) {}
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
      builder: (_) => CameraScreenStyle.qualitySheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CameraScreenStyle.sheetHandle(),
            const SizedBox(height: 20),
            CameraScreenStyle.sheetTitle,
            const SizedBox(height: 10),
            _buildSettingTile("Low Quality", ResolutionPreset.low),
            _buildSettingTile("Medium Quality", ResolutionPreset.medium),
            _buildSettingTile("High Quality (HD)", ResolutionPreset.high),
            _buildSettingTile("Very High Quality", ResolutionPreset.veryHigh),
            _buildSettingTile(
                "Ultra High Quality", ResolutionPreset.ultraHigh),
            _buildSettingTile("Max Quality", ResolutionPreset.max),
            const SizedBox(height: 20),
          ],
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
              cameraManager.controller!.value.previewSize!.width ==
                  preset.index
          ? const Icon(Icons.check, color: Colors.green)
          : const Icon(Icons.arrow_forward_ios,
              size: 16, color: Colors.white30),
      onTap: () async {
        await cameraManager.setCameraQuality(preset);
        Navigator.pop(context);
      },
    );
  }

  bool get _isVideoMode => _modeLabels[_currentModeIndex] == 'فيديو';

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _onCaptureTap() async {
    try {
      if (_isVideoMode) {
        await cameraManager.toggleVideoRecording();
      } else {
        await cameraManager.capture();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    if (cameraManager.controller == null ||
        !cameraManager.controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final controller = cameraManager.controller!;
    final bool isRecording = cameraManager.isRecording;
    final bool isRed = _isVideoMode || isRecording;

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
                    CameraScreenStyle.framedPreview(
                      CameraPreviewData(
                        preview: CameraPreview(controller),
                        previewSize: controller.value.previewSize,
                      ),
                    ),
                    if (isRecording)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: CameraScreenStyle.recordingTimer(
                          _formatDuration(cameraManager.recordingDuration),
                        ),
                      ),
                  ],
                ),

                // المساحة السودة تحت البريفيو، فيها أزرار التصوير
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
                            child: CameraScreenStyle.modeSlider(
                              controller: _modePageController,
                              modeLabels: _modeLabels,
                              currentModeIndex: _currentModeIndex,
                              onPageChanged: (index) {
                                setState(() => _currentModeIndex = index);
                              },
                            ),
                          ),
                          // زرار التصوير في المنتصف
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: CameraScreenStyle.captureButton(
                                isRecording: isRecording,
                                isRed: isRed,
                                onTap: _onCaptureTap,
                              ),
                            ),
                          ),
                          // زرار الفلاتر/الإضافات على اليمين
                          Positioned(
                            bottom: 27,
                            right: 24,
                            child: CameraScreenStyle.circularButton(
                              icon: Icons.auto_awesome,
                              color: Colors.white24,
                              onTap: () {},
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
          if (cameraManager.isVerifying) CameraScreenStyle.verifyingOverlay(),
        ],
      ),
    );
  }
}
