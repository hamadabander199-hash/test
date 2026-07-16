import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/crypto/native_crypto_service.dart';
import 'vault_item.dart';

/// شاشة عرض صورة (أو عدة صور بالـ swipe) full screen بخلفية سودا.
/// كل صورة بتتفك تشفيرها في الذاكرة بس وقت ما تظهر فعليًا (lazy)، من
/// الملف الأصلي المشفر (`originalFilePath`) — مش من الثامبنيل المخزّن.
class VaultPhotoViewer extends StatefulWidget {
  final List<VaultItem> photoItems;
  final int initialIndex;

  const VaultPhotoViewer({
    super.key,
    required this.photoItems,
    required this.initialIndex,
  });

  @override
  State<VaultPhotoViewer> createState() => _VaultPhotoViewerState();
}

class _VaultPhotoViewerState extends State<VaultPhotoViewer> {
  late final PageController _pageController;
  final Map<int, Uint8List> _decryptedCache = {};
  final Map<int, String> _errorCache = {};
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _decryptCurrent();
  }

  Future<void> _decryptCurrent() async {
    final index = _currentIndex;
    if (_decryptedCache.containsKey(index) ||
        _errorCache.containsKey(index)) {
      return;
    }
    try {
      final bytes = await NativeCryptoService.decryptToBytes(
        inputPath: widget.photoItems[index].originalFilePath,
      );
      if (!mounted) return;
      setState(() => _decryptedCache[index] = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorCache[index] = 'تعذّر فتح الصورة: $e');
    }
  }

  @override
  void dispose() {
    // بنمسح البايتات المفكوكة من الذاكرة فور الخروج من الشاشة.
    _decryptedCache.clear();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: widget.photoItems.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _decryptCurrent();
            },
            builder: (context, index) {
              final bytes = _decryptedCache[index];
              final error = _errorCache[index];

              if (error != null) {
                return PhotoViewGalleryPageOptions.customChild(
                  child: Center(
                    child: Text(error,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                );
              }

              if (bytes == null) {
                return PhotoViewGalleryPageOptions.customChild(
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                );
              }

              return PhotoViewGalleryPageOptions(
                imageProvider: MemoryImage(bytes),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
              );
            },
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
