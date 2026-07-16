import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'file_manager_controller.dart';

class FileManagerScreen extends StatefulWidget {
  @override
  _FileManagerScreenState createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final controller = FileManagerController();

  @override
  void initState() {
    super.initState();
    controller.loadFiles().then((_) => setState(() {}));
    controller.startFileWatcher((newFile) => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void shareSelected() {
    List<XFile> paths = controller.selectedFiles.map((f) => XFile(f.path)).toList();
    Share.shareXFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final files = controller.files;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Color(0xFF121212) : Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: controller.selectionMode ? Colors.blueGrey[900] : Colors.blueAccent[700],
        title: Text(
          controller.selectionMode
              ? "${controller.selectedFiles.length} Selected"
              : "My Secure Files",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (controller.selectionMode) ...[
            IconButton(
              icon: Icon(Icons.share_outlined, color: Colors.white),
              onPressed: shareSelected,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async => await _showDeleteConfirmDialog(context, false),
            ),
          ] else
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: Colors.white),
              tooltip: "Clear All",
              onPressed: () async => await _showDeleteConfirmDialog(context, true),
            ),
        ],
      ),
      body: files.isEmpty
          ? _buildEmptyState()
          : GridView.builder(
        padding: EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final isEncrypted = controller.isEncrypted(file);
          final isSelected = controller.selectedFiles.contains(file);
          final fileName = file.path.split('/').last;

          return GestureDetector(
            onTap: () {
              setState(() {
                if (controller.selectionMode) {
                  if (isSelected) controller.selectedFiles.remove(file);
                  else controller.selectedFiles.add(file);
                  if (controller.selectedFiles.isEmpty) controller.selectionMode = false;
                }
              });
            },
            onLongPress: () {
              setState(() {
                controller.selectionMode = true;
                controller.selectedFiles.add(file);
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Background Image or Icon
                    Container(
                      color: isSelected
                          ? Colors.blue.withOpacity(0.2)
                          : (isDark ? Colors.grey[850] : Colors.white),
                      child: Center(
                        child: isEncrypted
                            ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_person_rounded,
                                size: 40, color: Colors.amber[700]),
                            SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            )
                          ],
                        )
                            : Image.file(file,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity),
                      ),
                    ),

                    // Selection Overlay
                    if (isSelected)
                      Container(color: Colors.blue.withOpacity(0.3)),

                    // Top Badges
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        children: [
                          if (isSelected) _buildBadge(Icons.check_circle, Colors.blue),
                        ],
                      ),
                    ),

                    // Selection Radio for Selection Mode
                    if (controller.selectionMode && !isSelected)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Icon(Icons.radio_button_unchecked,
                            color: Colors.white.withOpacity(0.8), size: 20),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadge(IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined, size: 80, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            "No files found",
            style: TextStyle(
                fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, bool isAll) async {
    final count = isAll ? controller.files.length : controller.selectedFiles.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isAll ? "Delete All?" : "Confirm Delete"),
        content: Text(
            "Are you sure you want to delete $count file(s)? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm ?? false) {
      if (isAll) await controller.deleteAllFiles();
      else await controller.deleteSelected();
      setState(() {});
    }
  }
}