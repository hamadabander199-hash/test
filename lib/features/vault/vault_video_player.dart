import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/crypto/native_crypto_service.dart';
import 'vault_item.dart';

/// شاشة تشغيل فيديو واحد من الخزنة full screen.
///
/// الفيديو المشفّر مش بيتفك تشفيره في الذاكرة زي الصور (لأن VideoPlayer
/// محتاج مسار ملف حقيقي على القرص، مش bytes)، فبنفكه لملف مؤقت في
/// cache directory، ونشغّله من هناك، وبنمسحه فور الخروج من الشاشة.
class VaultVideoPlayerScreen extends StatefulWidget {
  final VaultItem videoItem;

  const VaultVideoPlayerScreen({super.key, required this.videoItem});

  @override
  State<VaultVideoPlayerScreen> createState() =>
      _VaultVideoPlayerScreenState();
}

class _VaultVideoPlayerScreenState extends State<VaultVideoPlayerScreen> {
  VideoPlayerController? _controller;
  File? _tempDecryptedFile;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _prepareAndPlay();
  }

  Future<void> _prepareAndPlay() async {
    try {
      final tempFile = await NativeCryptoService.decryptToTempFile(
        inputPath: widget.videoItem.originalFilePath,
        suggestedExtension: 'mp4',
      );

      final controller = VideoPlayerController.file(tempFile);
      await controller.initialize();

      if (!mounted) {
        // الشاشة اتقفلت أثناء التحميل - بنمسح الملف المؤقت فورًا.
        await controller.dispose();
        await tempFile.delete().catchError((_) => tempFile);
        return;
      }

      setState(() {
        _tempDecryptedFile = tempFile;
        _controller = controller;
        _isLoading = false;
      });

      controller
        ..setLooping(true)
        ..play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر فتح الفيديو: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    // مسح الملف المؤقت المفكوك من الـ cache فور الخروج من الشاشة، عشان
    // النسخة الغير مشفّرة متفضلش على القرص.
    final tempFile = _tempDecryptedFile;
    if (tempFile != null) {
      tempFile.delete().catchError((_) => tempFile);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: _buildBody()),
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

  Widget _buildBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    if (_isLoading || _controller == null || !_controller!.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white70);
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _controller!.value.isPlaying
              ? _controller!.pause()
              : _controller!.play();
        });
      },
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}
