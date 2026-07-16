import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// تم شيل كل التعامل مع Firebase Storage نهائيًا: الكنترولر ده بقى
/// بيتعامل مع الملفات محليًا بس (عرض / تحديد / حذف) من غير أي رفع
/// لأي مكان.
class FileManagerController {
  List<File> files = [];
  Set<File> selectedFiles = {};
  bool selectionMode = false;

  StreamSubscription<FileSystemEvent>? _watcher;

  // ===== Public Methods =====

  Future<void> loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final allFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && isSupportedFile(entity)) {
          allFiles.add(entity);
        }
      }
    } catch (_) {}

    files = allFiles;
  }

  void startFileWatcher(void Function(File) onNewFile) async {
    final dir = await getApplicationDocumentsDirectory();
    _watcher = dir.watch(recursive: true).listen((event) {
      if (event is FileSystemCreateEvent) {
        final file = File(event.path);
        if (isSupportedFile(file)) {
          files.add(file);
          onNewFile(file);
        }
      }
    });
  }

  void dispose() {
    _watcher?.cancel();
  }

  bool isSupportedFile(File file) {
    return file.path.endsWith(".jpg") ||
        file.path.endsWith(".png") ||
        file.path.endsWith(".enc") ||
        file.path.endsWith(".mp4");
  }

  bool isEncrypted(File file) => file.path.endsWith(".enc");

  Future<void> deleteAllFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final allEntities = dir.listSync(recursive: true);

    for (var entity in allEntities) {
      try {
        if (entity is File) await entity.delete();
        else if (entity is Directory) await entity.delete(recursive: true);
      } catch (e) {
      }
    }

    files.clear();
    selectedFiles.clear();
    selectionMode = false;
  }

  Future<void> deleteSelected() async {
    for (var file in selectedFiles) {
      try {
        await file.delete();
        files.remove(file);
      } catch (e) {
      }
    }
    selectedFiles.clear();
    selectionMode = false;
  }
}