import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../Services/LoopbackVideoServer.dart';
import '../../Services/NativeCryptoService.dart';
import '../../theme/app_theme.dart';
import 'vault_item.dart';

/// شاشة تشغيل فيديو مشفّر.
///
/// التنفيذ: فك تشفير الملف بالكامل في الذاكرة عن طريق
/// `NativeCryptoService.decryptToBytes` (زي ما اتفق عليه — مش chunk
/// streaming حرفي)، وبعدين تقديم البايتات دي لـ `video_player` عن طريق
/// سيرفر HTTP محلي على 127.0.0.1 بس ([LoopbackVideoServer])، عشان
/// نستفيد من عناصر التحكم العادية (تشغيل/إيقاف/شريط تقدم/seek) من غير
/// ما نكتب أي بايت plaintext على التخزين في أي لحظة.
class VaultVideoPlayerScreen extends StatefulWidget {
  final VaultItem videoItem;

  const VaultVideoPlayerScreen({super.key, required this.videoItem});

  @override
  State<VaultVideoPlayerScreen> createState() =>
      _VaultVideoPlayerScreenState();
}

class _VaultVideoPlayerScreenState extends State<VaultVideoPlayerScreen> {
  VideoPlayerController? _controller;
  LoopbackVideoServer? _server;

  bool _loading = true;
  String? _error;
  bool _seekBuffering = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final bytes = await NativeCryptoService.decryptToBytes(
        inputPath: widget.videoItem.originalFilePath,
      );

      final server = LoopbackVideoServer(bytes);
      final url = await server.start();
      _server = server;

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.addListener(_onControllerUpdate);

      if (!mounted) {
        await controller.dispose();
        await server.stop();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
      });
      controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تشغيل الفيديو: $e';
      });
    }
  }

  void _onControllerUpdate() {
    final c = _controller;
    if (c == null) return;
    final buffering = c.value.isBuffering;
    if (buffering != _seekBuffering) {
      setState(() => _seekBuffering = buffering);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    // بنقفل السيرفر المحلي، والبايتات المفكوكة بتتشال من الذاكرة معاه.
    _server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_loading)
              const CircularProgressIndicator(color: Colors.white70)
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            else if (_controller != null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller!),
                            if (_seekBuffering)
                              const CircularProgressIndicator(
                                  color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildControls(),
                ],
              ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final controller = _controller!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.primary,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white10,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    controller.value.isPlaying
                        ? controller.pause()
                        : controller.play();
                  });
                },
              ),
              Text(
                '${_fmt(controller.value.position)} / ${_fmt(controller.value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  controller.value.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    controller.setVolume(
                        controller.value.volume == 0 ? 1 : 0);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
