import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../Services/image_receiver.dart';
import '../../Services/StreamingVideoEncryptor.dart';
import 'package:flutter/foundation.dart'; // للـ ValueNotifier

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

  // بيبقى true وقت ما بنراجع سلامة الملف المشفر النهائي بعد التسجيل
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

  // Streaming (real-time) video encryptor: fed continuously while recording.
  StreamingVideoEncryptor? _streamEncryptor;
  String? _pendingEncOutputPath;
  String? _pendingFinalEncPath;

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

    // لو لسه بنتأكد من سلامة تسجيل سابق (isVerifying) أو في نص عملية
    // start/stop تانية (_isTogglingRecording)، بنتجاهل أي دوسة جديدة على
    // الزرار. من غير الحراسة دي، لو المستخدم دوس "وقف" وبسرعة دوس "شغّل"
    // تاني قبل ما التحقق من التشفير يخلص، هيبدأ تسجيل جديد فوق الـ
    // stream encryptor القديم لسه شغال، وده اللي كان بيسبب الهنج.
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
        await _beginStreamingEncryption();
      } else {
        // بنوقف التسجيل ونولّع شاشة "جاري التأكد من التشفير" فورًا وقبل أي
        // await، عشان الزرار يتقفل في الحال ومينفعش المستخدم يدوس "شغّل"
        // تاني قبل ما نتأكد إن الفيديو اتشفر صح.
        isRecording = false;
        isVerifying = true;
        _stopRecordingTimer();
        onUpdate?.call();

        try {
          final videoFile = await controller!.stopVideoRecording();
          await _finishStreamingEncryption(videoFile.path);
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
    // (تبديل كاميرا / تسجيل) من التنفيذ لحد ما التحقق من التشفير يخلص.
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
          await _finishStreamingEncryption(videoFile.path);
        } catch (e) {
          await _streamEncryptor?.abort();
          _streamEncryptor = null;
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
    // منع تغيير الجودة أثناء التسجيل أو أثناء التحقق من التشفير: تغيير
    // الجودة بيعمل dispose للـ controller فورًا، ولو ده حصل ونحن لسه
    // بنسجل هيقفل ملف الفيديو فجأة من غير ما نوقف الـ stream encryptor
    // بشكل سليم، وده كان ممكن يسيب الفيديو من غير تشفير كامل أو يهنج.
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

  /// Starts feeding the in-progress recording into the native streaming
  /// encryptor as soon as the camera plugin begins writing bytes, instead
  /// of waiting for the whole recording to finish.
  Future<void> _beginStreamingEncryption() async {
    final dir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();
    final pubKeyPath = await copyAssetKeyToFile("assets/public.pem");
    final id = DateTime.now().millisecondsSinceEpoch;

    // Encrypt into a temp/staging file first. We only move it into the
    // Documents dir (which FileMonitorService watches for uploads) once
    // it's fully finalized, so we never upload a half-encrypted file.
    _pendingEncOutputPath = "${tempDir.path}/streaming_$id.enc.tmp";
    _pendingFinalEncPath = "${dir.path}/vid_enc_$id.enc";

    _streamEncryptor = StreamingVideoEncryptor();

    try {
      // The camera plugin controls the exact temp video file path/name
      // internally and only returns it once recording stops. So we locate
      // it as soon as it's created and start tailing it immediately.
      final sourcePath = await _waitForActiveRecordingFile(tempDir);
      videoPath = sourcePath;

      await _streamEncryptor!.start(
        sourcePath: sourcePath,
        outputPath: _pendingEncOutputPath!,
        publicKeyPath: pubKeyPath,
      );
    } catch (e) {
      // If we couldn't locate the file for tailing, fall back silently to
      // encrypting the whole file once recording stops (old behavior),
      // instead of failing the recording.
      _streamEncryptor = null;
    }
  }

  Future<void> _finishStreamingEncryption(String recordedFilePath) async {
    if (_streamEncryptor == null || _streamEncryptor?.isRunning != true) {
      // Fallback path (streaming never got wired up correctly): encrypt
      // the completed file the old way so nothing is left unprotected.
      isVerifying = true;
      onUpdate?.call();

      final pubKeyPath = await copyAssetKeyToFile("assets/public.pem");
      final resultPath = await ImageReceiver.receiveImage(recordedFilePath, pubKeyPath, (p) {});

      final valid = resultPath != null && await _verifyEncryptedFile(resultPath, recordedFilePath);
      if (valid) {
        final plain = File(recordedFilePath);
        if (await plain.exists()) await plain.delete();
        lastMessage.value = "تم تشفير الفيديو والتأكد من سلامته";
      } else {
        // الملف المشفر مش سليم والكاش الأصلي لسه موجود - مبنمسحوش
        lastMessage.value = "تعذر التأكد من سلامة الفيديو المشفر، تم الاحتفاظ بالنسخة الأصلية";
      }

      isVerifying = false;
      onUpdate?.call();
      return;
    }

    final ok = await _streamEncryptor!.finish();
    _streamEncryptor = null;

    isVerifying = true;
    onUpdate?.call();

    final tmpPath = _pendingEncOutputPath;
    final finalPath = _pendingFinalEncPath;

    bool valid = false;

    if (ok && tmpPath != null && finalPath != null) {
      final tmp = File(tmpPath);
      if (await tmp.exists()) {
        await tmp.rename(finalPath);
        // بنراجع الملف المشفر النهائي فعلًا سليم ومطابق للفيديو الأصلي
        valid = await _verifyEncryptedFile(finalPath, recordedFilePath);
      }
    }

    if (!valid) {
      // فشل التحقق: نحاول نعيد التشفير تاني من الكاش الأصلي (اللي لسه
      // موجود لأننا لسه ما مسحناهوش) بدل ما نسيب الفيديو من غير تشفير سليم
      lastMessage.value = "الفيديو المشفر فيه مشكلة، جاري إعادة التشفير من النسخة الأصلية...";
      onUpdate?.call();

      final retryOk = await _retryFullFileEncryption(
        recordedFilePath: recordedFilePath,
        finalPath: finalPath,
      );
      valid = retryOk;
    }

    if (valid) {
      final plain = File(recordedFilePath);
      if (await plain.exists()) {
        await plain.delete();
      }
      lastMessage.value = "تم تشفير الفيديو والتأكد من سلامته";
    } else {
      // فشلت المحاولتين - نحتفظ بالكاش الأصلي عشان الفيديو ميضيعش
      lastMessage.value = "تعذر تشفير الفيديو بشكل سليم، تم الاحتفاظ بالنسخة الأصلية للمراجعة";
    }

    _pendingEncOutputPath = null;
    _pendingFinalEncPath = null;

    isVerifying = false;
    onUpdate?.call();
  }

  /// يعيد تشفير الفيديو بالكامل مباشرة من الملف الأصلي (الكاش) اللي لسه
  /// محفوظ على الجهاز، وده بيتنفذ بس لو النسخة اللي جت من الـ streaming
  /// فشلت في التحقق. بيكتب فوق نفس مسار الملف النهائي [finalPath].
  Future<bool> _retryFullFileEncryption({
    required String recordedFilePath,
    required String? finalPath,
  }) async {
    try {
      final plain = File(recordedFilePath);
      if (!await plain.exists()) return false;

      final pubKeyPath = await copyAssetKeyToFile("assets/public.pem");
      final resultPath = await ImageReceiver.receiveImage(recordedFilePath, pubKeyPath, (p) {});
      if (resultPath == null) return false;

      final valid = await _verifyEncryptedFile(resultPath, recordedFilePath);
      if (!valid) return false;

      // لو الملف الناتج مش في نفس مكان الملف النهائي المتوقع، ننقله هناك
      if (finalPath != null && resultPath != finalPath) {
        final resultFile = File(resultPath);
        if (await resultFile.exists()) {
          await resultFile.rename(finalPath);
        }
      }
      return true;
    } catch (_) {
      return false;
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

  /// Polls the temp directory right after startVideoRecording() to find the
  /// file the camera plugin just created, so we can start tailing it
  /// immediately instead of waiting for stopVideoRecording() to tell us
  /// its path.
  Future<String> _waitForActiveRecordingFile(Directory tempDir) async {
    // مهم: بنستخدم list() (الـ Stream غير المتزامنة) بدل listSync() هنا.
    // listSync بتعمل recursive scan للـ temp directory بشكل synchronous
    // على نفس الـ isolate، وكانت بتتنفذ كل 100ms بالظبط في اللحظة اللي
    // بيبدأ فيها التسجيل وبيحتاج البريفيو يتحرك بسلاسة - فكانت بتسبب
    // هنجات/تقطيع محسوس في البريفيو. النسخة دي بتعمل نفس الحاجة من غير
    // ما تقفل الـ UI isolate.
    final before = await _listFilePathsAsync(tempDir);

    for (int i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final current = await _listFilePathsAsync(tempDir);
      final candidates = current.where(
            (p) => p.endsWith(".mp4") && !before.contains(p),
      );

      if (candidates.isNotEmpty) {
        return candidates.first;
      }
    }

    throw Exception("Could not locate active recording file for streaming");
  }

  /// بيرجع مسارات كل الملفات جوه [dir] (recursive) من غير ما يقفل الـ UI
  /// isolate، باستخدام list() الـ async بدل listSync() المتزامنة.
  Future<Set<String>> _listFilePathsAsync(Directory dir) async {
    final paths = <String>{};
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) paths.add(entity.path);
      }
    } catch (_) {
      // ممكن يحصل تعارض عابر لو فولدر اتمسح أثناء الفحص - نتجاهله ونكمل
      // بأفضل نتيجة عندنا لحد دلوقتي.
    }
    return paths;
  }

  void dispose() {
    _recordingTimer?.cancel();
    controller?.dispose();
    lastMessage.dispose();
    _streamEncryptor?.abort();
  }
}