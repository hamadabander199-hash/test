import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// بيراقب مجلد الـ Documents محليًا بس (رصد ملفات جديدة/موجودة) من غير
/// أي رفع لأي مكان. تم شيل كل التعامل مع Firebase Storage نهائيًا.
class FileMonitorService {
  final List<File> files = [];

  StreamSubscription<FileSystemEvent>? _watcher;

  /// يبدأ المراقبة
  Future<void> startMonitoring() async {
    final dir = await getApplicationDocumentsDirectory();

    // جلب كل الملفات الحالية أول مرة
    await _loadExistingFiles(dir);

    // بدء المراقبة الحية
    _watcher = dir.watch(recursive: true).listen((event) {
      if (event is FileSystemCreateEvent) {
        final file = File(event.path);
        if (_isSupportedFile(file)) {
          files.add(file);
        }
      }
    });
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _watcher?.cancel();
  }

  /// تحميل الملفات الموجودة مسبقًا (async عشان مايقفلش الـ UI isolate
  /// لو كان فيه عدد كبير من الملفات في الـ Documents directory)
  Future<void> _loadExistingFiles(Directory dir) async {
    final existingFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isSupportedFile(entity)) {
          existingFiles.add(entity);
        }
      }
    } catch (_) {}

    files.addAll(existingFiles);
  }

  bool _isSupportedFile(File file) {
    return file.path.endsWith(".jpg") ||
        file.path.endsWith(".png") ||
        file.path.endsWith(".enc") ||
        file.path.endsWith(".mp4");
  }

  bool _isEncrypted(File file) {
    return file.path.endsWith(".enc");
  }
}