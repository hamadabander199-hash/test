import 'dart:io';
import 'dart:typed_data';

/// سيرفر HTTP محلي بيسمع بس على 127.0.0.1 (loopback — مش قابل للوصول من
/// أي جهاز تاني على الشبكة) وبيقدّم بايتات فيديو **من الرام مباشرة**.
///
/// السبب: `video_player` (زي ExoPlayer/AVPlayer اللي بيستخدمهم من تحت)
/// مش بيقبل تشغيل من `Uint8List` مباشرة — محتاج مصدر (ملف أو URL). بدل
/// ما نكتب الفيديو المفكوك كملف plaintext على القرص (ممنوع حسب سياسة
/// الأمان)، بنعمل سيرفر مؤقت في نفس العملية بيقدّم البايتات دي كـ
/// "http://127.0.0.1:port/video" مع دعم Range requests عشان الـ seek
/// يشتغل عادي، وبنقفل السيرفر فور ما المستخدم يخرج من شاشة التشغيل.
///
/// النتيجة: البايتات المفكوكة بتفضل في الرام بس طول الوقت، ومفيش أي جزء
/// منها بيتكتب على التخزين في أي لحظة.
class LoopbackVideoServer {
  HttpServer? _server;
  final Uint8List videoBytes;
  final String mimeType;

  LoopbackVideoServer(this.videoBytes, {this.mimeType = 'video/mp4'});

  /// بيبدأ السيرفر على بورت عشوائي فاضي على loopback بس، ويرجّع الـ URL.
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    return 'http://127.0.0.1:${_server!.port}/video';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final total = videoBytes.length;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType =
        ContentType.parse(mimeType);

    if (rangeHeader == null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, total);
      request.response.add(videoBytes);
      await request.response.close();
      return;
    }

    // بارسينج بسيط لـ "bytes=start-end"
    final match =
        RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
    int start = 0;
    int end = total - 1;

    if (match != null) {
      final startStr = match.group(1) ?? '';
      final endStr = match.group(2) ?? '';
      if (startStr.isNotEmpty) start = int.parse(startStr);
      if (endStr.isNotEmpty) end = int.parse(endStr);
    }
    if (end >= total) end = total - 1;
    if (start > end) start = end;

    final chunk = videoBytes.sublist(start, end + 1);

    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$total',
    );
    request.response.headers
        .set(HttpHeaders.contentLengthHeader, chunk.length);
    request.response.add(chunk);
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
