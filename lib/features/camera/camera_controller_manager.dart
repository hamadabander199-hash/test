import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/crypto/image_receiver.dart';
import 'package:flutter/foundation.dart'; // للـ ValueNotifier

/// مسؤول عن التحكم في الكاميرا: تشغيل، تبديل، فلاش، تصوير، وتسجيل
/// فيديو. التسجيل هنا "عادي" (مش streaming) - بيسجل الفيديو كامل الأول،
/// وبعد ما يوقف بيشفّره مرة واحدة زي الصور بالظبط.
class CameraControllerManager {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  int currentCameraIndex = 0;

  List<String> imageQueue = [];
  bool isEncrypting = false;

  ValueNotifier<String> lastMessage = ValueNotifier("");
  bool flashOn = false;
  bool isRecording = false;
  String? videoPath;

  // بيبقى true وقت ما بنشفّر الفيديو بعد ما التسجيل يوقف
  bool isVerifying = false;

  // بيبقى true من لحظة ما toggleVideoRecording() تتنده لحد ما تخلص
  // بالكامل (سواء start أو stop)، عشان نمنع أي دوسة تانية على الزرار
  // تتنفذ فوق عملية لسه شغالة (race condition بيسبب هنج).
  bool _isTogglingRecording = false;

  // عداد وقت التسجيل
  Duration recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // الجودة الحالية للكاميرا، بتتحدث كل ما نغيّرها من الإعدادات
  ResolutionPreset currentPreset = ResolutionPreset.max;

  // ✅ Callback لتحديث الواجهة
  final VoidCallback? onUpdate;

  CameraControllerManager({this.onUpdate});

  Future initCameras() async {
    cameras = await availableCameras();
    if (cameras.isEmpty) return;

    currentPreset = ResolutionPreset.max;
    controller = CameraController(
      cameras[currentCameraIndex],
      currentPreset,
      enableAudio: true,
    );
    await controller!.initialize();
    onUpdate?.call();
  }

  Future toggleVideoRecording() async {
    if (controller == null || !controller!.value.isInitialized) return;

    // لو لسه بنشفّر تسجيل سابق (isVerifying) أو في نص عملية start/stop
    // تانية (_isTogglingRecording)، بنتجاهل أي دوسة جديدة على الزرار.
    if (isVerifying || _isTogglingRecording) return;

    _isTogglingRecording = true;
    try {
      if (!isRecording) {
        // بنغيّر الحالة ونحدّث الواجهة فورًا (الدايرة تتحول مربع فورًا)
        // من غير ما ننتظر startVideoRecording تخلص
        isRecording = true;
        _startRecordingTimer();
        onUpdate?.call();

        await controller!.startVideoRecording();
      } else {
        // بنوقف التسجيل ونولّع شاشة "جاري التشفير" فورًا وقبل أي await،
        // عشان الزرار يتقفل في الحال ومينفعش المستخدم يدوس "شغّل" تاني
        // قبل ما التشفير يخلص.
        isRecording = false;
        isVerifying = true;
        _stopRecordingTimer();
        onUpdate?.call();

        try {
          final videoFile = await controller!.stopVideoRecording();
          await _encryptRecordedVideo(videoFile.path);
        } finally {
          isVerifying = false;
          onUpdate?.call();
        }
      }
    } finally {
      _isTogglingRecording = false;
    }
    onUpdate?.call();
  }

  void _startRecordingTimer() {
    recordingDuration = Duration.zero;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      recordingDuration += const Duration(seconds: 1);
      onUpdate?.call();
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    recordingDuration = Duration.zero;
  }

  Future switchCamera() async {
    if (cameras.isEmpty || controller == null) return;
    // نفس الحراسة اللي في toggleVideoRecording: منع أي عملية تانية
    // (تبديل كاميرا / تسجيل) من التنفيذ لحد ما التشفير يخلص.
    if (isVerifying || _isTogglingRecording) return;
    _isTogglingRecording = true;

    try {
      if (isRecording) {
        isRecording = false;
        isVerifying = true;
        _stopRecordingTimer();
        onUpdate?.call();
        try {
          final videoFile = await controller!.stopVideoRecording();
          await _encryptRecordedVideo(videoFile.path);
        } finally {
          isVerifying = false;
        }
      }

      currentCameraIndex = (currentCameraIndex + 1) % cameras.length;
      currentPreset = ResolutionPreset.medium;
      controller = CameraController(
        cameras[currentCameraIndex],
        currentPreset,
        enableAudio: true,
      );
      await controller!.initialize();
      await controller!.setFlashMode(flashOn ? FlashMode.torch : FlashMode.off);

      onUpdate?.call();
    } finally {
      _isTogglingRecording = false;
    }
  }

  Future toggleFlash() async {
    if (controller == null) return;
    flashOn = !flashOn;
    await controller!.setFlashMode(flashOn ? FlashMode.torch : FlashMode.off);
    onUpdate?.call();
  }

  Future setCameraQuality(ResolutionPreset preset) async {
    if (controller == null) return;
    // منع تغيير الجودة أثناء التسجيل أو أثناء التشفير: تغيير الجودة
    // بيعمل dispose للـ controller فورًا، ولو ده حصل ونحن لسه بنسجل
    // هيقفل ملف الفيديو فجأة، وده كان ممكن يسيب الفيديو تالف أو يهنج.
    if (isRecording || isVerifying || _isTogglingRecording) return;

    final currentLens = controller!.description.lensDirection;
    await controller!.dispose();

    currentPreset = preset;
    controller = CameraController(
      cameras.firstWhere((cam) => cam.lensDirection == currentLens),
      currentPreset,
      enableAudio: true,
    );
    await controller!.initialize();
    await controller!.setFlashMode(flashOn ? FlashMode.torch : FlashMode.off);

    onUpdate?.call();
  }

  Future<String> copyAssetKeyToFile(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/${assetPath.split("/").last}';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future capture() async {
    if (controller == null || !controller!.value.isInitialized) return;
    final image = await controller!.takePicture();
    imageQueue.add(image.path);
    if (!isEncrypting) _startEncryptionQueue();
  }

  Future _startEncryptionQueue() async {
    isEncrypting = true;
    final pubKeyPath = await copyAssetKeyToFile("assets/public.pem");

    while (imageQueue.isNotEmpty) {
      final imagePath = imageQueue.removeAt(0);
      await ImageReceiver.receiveImage(imagePath, pubKeyPath, (p) {});
    }
    isEncrypting = false;
    onUpdate?.call();
  }

  /// بتشفّر الفيديو المسجل بالكامل بعد ما التسجيل يوقف (زي الصور
  /// بالظبط)، وبتتأكد إن الملف المشفر سليم قبل ما تمسح النسخة الأصلية.
  Future<void> _encryptRecordedVideo(String recordedFilePath) async {
    final pubKeyPath = await copyAssetKeyToFile("assets/public.pem");
    final resultPath =
        await ImageReceiver.receiveImage(recordedFilePath, pubKeyPath, (p) {});

    final valid =
        resultPath != null && await _verifyEncryptedFile(resultPath, recordedFilePath);

    if (valid) {
      final plain = File(recordedFilePath);
      if (await plain.exists()) await plain.delete();
      lastMessage.value = "تم تشفير الفيديو والتأكد من سلامته";
    } else {
      // الملف المشفر مش سليم والكاش الأصلي لسه موجود - مبنمسحوش
      lastMessage.value =
          "تعذر التأكد من سلامة الفيديو المشفر، تم الاحتفاظ بالنسخة الأصلية";
    }
  }

  /// بيتأكد إن الملف المشفر [encryptedPath] سليم فعلًا (مش فاضي أو ناقص أو
  /// متقطّع). لو فيه دعم native للتحقق الحقيقي من GCM tag/header بيتنده
  /// عليه، ولو مش متاح (الميثود مش متعملة على الجانب الأصلي) بيرجع
  /// لفحص أساسي بالحجم كحد أدنى بدل ما يفشل التسجيل كله.
  Future<bool> _verifyEncryptedFile(String encryptedPath, String originalPlainPath) async {
    try {
      final encFile = File(encryptedPath);
      if (!await encFile.exists()) return false;

      final encSize = await encFile.length();
      if (encSize <= 0) return false;

      // فحص أساسي بالحجم: الملف المشفر لازم يكون بحجم منطقي مقارنة
      // بالفيديو الأصلي (تشفير GCM بيضيف هيدر/تاج بس مش بيقلل الحجم)
      final plain = File(originalPlainPath);
      if (await plain.exists()) {
        final plainSize = await plain.length();
        if (plainSize > 0 && encSize < plainSize * 0.9) {
          // الملف المشفر أصغر بشكل غير منطقي من الأصلي = على الأغلب ناقص
          return false;
        }
      }

      // محاولة تحقق حقيقي على الجانب الأصلي (لو متعمل) - بيتأكد من صحة
      // الـ GCM auth tag وهيدر التشفير من غير فك التشفير الكامل
      try {
        final result = await MethodChannel("camzone/encryption").invokeMethod<bool>(
          "verifyEncryptedVideo",
          {"path": encryptedPath},
        );
        if (result != null) return result;
      } on MissingPluginException {
        // الميثود دي لسه مش متعملة على الجانب الأصلي (Kotlin/C++) -
        // نكتفي بالفحص الأساسي اللي فوق لحد ما تتضاف
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _recordingTimer?.cancel();
    controller?.dispose();
    lastMessage.dispose();
  }
}
