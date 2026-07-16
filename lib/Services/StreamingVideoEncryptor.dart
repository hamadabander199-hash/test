import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Encrypts a video file in near real-time WHILE it's still being recorded,
/// instead of waiting for recording to finish and encrypting the whole file
/// in one pass. Memory use stays constant regardless of video length, and
/// the work is spread out over the recording instead of happening all at
/// once when the user stops.
///
/// How it works:
/// - Polls the source file (the temp .mp4 the camera plugin is actively
///   writing to) every [pollInterval].
/// - Reads only the NEW bytes appended since the last poll.
/// - Sends those bytes to the native AES-GCM stream encryptor, which
///   encrypts them immediately and writes ciphertext to [outputPath].
/// - On [finish], drains any remaining bytes and finalizes the GCM tag.
class StreamingVideoEncryptor {
  static const MethodChannel _channel = MethodChannel("camzone/encryption");

  int? _handle;
  String? _sourcePath;
  int _bytesSent = 0;
  Timer? _pollTimer;
  bool _busy = false;

  final Duration pollInterval;

  StreamingVideoEncryptor({this.pollInterval = const Duration(milliseconds: 250)});

  bool get isRunning => _handle != null;

  /// Starts the streaming session. [sourcePath] is the file the camera is
  /// actively recording to (it may not exist yet at the very first instant
  /// recording starts — that's fine, the poll loop will pick it up).
  Future<void> start({
    required String sourcePath,
    required String outputPath,
    required String publicKeyPath,
  }) async {
    _sourcePath = sourcePath;
    _bytesSent = 0;

    final handle = await _channel.invokeMethod<int>("startStreamEncryption", {
      "outputPath": outputPath,
      "publicKeyPath": publicKeyPath,
    });

    if (handle == null || handle == 0) {
      throw Exception("Failed to start native stream encryption");
    }
    _handle = handle;

    _pollTimer = Timer.periodic(pollInterval, (_) => _pump());
  }

  Future<void> _pump() async {
    if (_busy || _handle == null || _sourcePath == null) return;
    _busy = true;
    try {
      final file = File(_sourcePath!);
      if (!await file.exists()) return;

      final length = await file.length();
      if (length <= _bytesSent) return;

      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(_bytesSent);
        final chunk = await raf.read(length - _bytesSent);
        if (chunk.isNotEmpty) {
          final ok = await _channel.invokeMethod<bool>("feedStreamEncryption", {
            "handle": _handle,
            "data": chunk,
          });
          if (ok == true) {
            _bytesSent += chunk.length;
          }
        }
      } finally {
        await raf.close();
      }
    } catch (_) {
      // Transient read races with the recorder writing the same file are
      // expected occasionally; the next poll tick will catch up.
    } finally {
      _busy = false;
    }
  }

  /// Call once recording has stopped. Drains trailing bytes and finalizes
  /// the encrypted output (writes the GCM auth tag, closes the file).
  Future<bool> finish() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    // Catch bytes written right up to the moment recording stopped, plus
    // any final flush the recorder does after stopVideoRecording() returns.
    await _pump();
    await Future.delayed(const Duration(milliseconds: 150));
    await _pump();

    if (_handle == null) return false;

    final ok = await _channel.invokeMethod<bool>("finishStreamEncryption", {
      "handle": _handle,
    });
    _handle = null;
    return ok == true;
  }

  /// Call if recording is cancelled/interrupted instead of stopped normally.
  Future<void> abort() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_handle != null) {
      await _channel.invokeMethod("abortStreamEncryption", {"handle": _handle});
      _handle = null;
    }
  }
}