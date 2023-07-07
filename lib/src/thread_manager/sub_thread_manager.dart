import 'dart:isolate';

import '../download_chunk/download_chunk.dart';

class SubThreadManager {
  late PartDownload partDownload;

  Future startDownload({
    required String url,
    required String savePath,
    required int index,
    required int start,
    required int end,
    required SendPort sendPort,
  }) async {
    partDownload = PartDownload(
        url: url,
        savePath: savePath,
        index: index,
        start: start,
        end: end,
        sendPort: sendPort);
    await partDownload.startDownload();
  }

  void stopDownload() {
    partDownload.stopDownload();
  }
}
