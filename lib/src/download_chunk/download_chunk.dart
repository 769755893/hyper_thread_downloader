import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:hyper_thread_downloader/src/base/task.dart';
import 'package:hyper_thread_downloader/src/interface/hyper_interface.dart';
import 'package:hyper_thread_downloader/src/model/thread_status.dart';
import 'package:hyper_thread_downloader/src/util/log_util.dart';

final partialExtension = '.partial';
final tempExtension = '.temp';

enum PrepareStatus {
  partialExists,
  partDone,
}

class PartDownload with Task {
  String url;
  String savePath;
  int index;

  String get partPartialFileName => '$savePath$partialExtension.$index';

  String get partTempFileName =>
      '$savePath$partialExtension$tempExtension.$index';

  String get partFileName => '$savePath.$index';

  File? partialFile;

  int partialFileLength = 0;

  int start;
  int end;
  SendPort sendPort;

  PartDownload({
    required this.url,
    required this.savePath,
    required this.index,
    required this.start,
    required this.end,
    required this.sendPort,
  });

  late Dio dio;
  late CancelToken cancelToken;

  void _sendStatus(ThreadStatus status) {
    HyperLog.log('subThread: $index, sendStatus');
    sendPort.send({
      'status': status.value,
      'index': index,
    });
  }

  void _downloadComplete() {
    print('subThread: $index, downloadComplete');
    Isolate.exit(sendPort, {
      'status': ThreadStatus.downloadComplete.value,
      'index': index,
    });
  }

  Future cleanFile() async {
    final f0 = File(partTempFileName);
    final f1 = File(partFileName);
    final f2 = File(partPartialFileName);
    await run(
        futureBlock: () async {
          f0.deleteSync(recursive: true);
        },
        fallback: (e) {});
    await run(
        futureBlock: () async {
          f1.deleteSync(recursive: true);
        },
        fallback: (e) {});
    await run(
        futureBlock: () async {
          f2.deleteSync(recursive: true);
        },
        fallback: (e) {});
  }

  void _downloadFailed(String reason) async {
    HyperLog.log('subThread: $index, downloadFailed with reason: $reason');
    await cleanFile();
    Isolate.exit(sendPort, {
      'status': ThreadStatus.downloadFailed.value,
      'index': index,
      'value': reason,
    });
  }

  void _downloadFailedWithSocket(String reason) async {
    Isolate.exit(sendPort, {
      'status': ThreadStatus.downloadFailed.value,
      'index': index,
      'value': reason,
    });
  }

  void _downloadSpeed({required int cur, required int total}) {
    sendPort.send({
      'status': ThreadStatus.downloading.value,
      'index': index,
      'cur': cur,
      'total': total,
    });
  }

  Future startDownload() async {
    _sendStatus(ThreadStatus.working);
    dio = Dio()..options = BaseOptions(connectTimeout: Duration(seconds: 5));
    cancelToken = CancelToken();
    bool error = false;
    PrepareStatus status = await downloadPrepare(fallback: (e) {
      _downloadFailed(e);
      error = true;
    });
    if (error) return;
    switch (status) {
      case PrepareStatus.partDone:
        HyperLog.log(
            'find complete sub part, sub thread: $index download complete');
        _downloadComplete();
        break;
      case PrepareStatus.partialExists:
        partialFileLength = partialFile?.lengthSync() ?? 0;
        print('partialFileLength: $partialFileLength');
        try {
          final res = await dio.download(
            url,
            partTempFileName,
            onReceiveProgress: (int cur, int total) => _downloadSpeed(
              cur: cur + partialFileLength,
              total: total + partialFileLength,
            ),
            options: Options(headers: {
              HttpHeaders.rangeHeader: 'bytes=${start + partialFileLength}-$end'
            }),
            cancelToken: cancelToken,
            deleteOnError: false,
          );
          await Future.delayed(Duration(seconds: 2));
          if (res.statusCode == HttpStatus.partialContent) {
            await mergeTemp(fallback: (e) {
              _downloadFailed(e);
              error = true;
            });
            if (error) return;
            await renameFile(failed: (String reason) {
              _downloadFailed(reason);
              error = true;
            });
            if (error) return;
            _downloadComplete();
            return;
          }
          final msg = jsonEncode(
            {
              'statusCode': res.statusCode,
              'data': res.data.toString(),
            },
          );
          HyperLog.log('download failed with incomplete code: $msg');
          _downloadFailed(msg);
        } on DioError catch (e) {
          if (e.type == DioErrorType.cancel) {
            HyperLog.log('download cancel sub thread: $index');
            return;
          }
          if (e.error is SocketException) {
            HyperLog.log('download failed with socket exception');
            _downloadFailedWithSocket('download failed with ${e.error}');
            return;
          }
          final msg = 'download failed with dio error: $e, ${e.error}';
          HyperLog.log(msg);
          _downloadFailed(msg);
        } catch (e) {
          final msg = 'download failed with unknown error: $e';
          HyperLog.log(msg);
          _downloadFailed(msg);
        }
        break;
      default:
        break;
    }
  }

  Future<PrepareStatus> downloadPrepare({
    required DownloadFailed fallback,
  }) async {
    final partDoneFile = File(partFileName);
    if (partDoneFile.existsSync()) return PrepareStatus.partDone;
    final tempFile = File(partTempFileName);
    if (tempFile.existsSync()) {
      await mergeTemp(fallback: fallback);
    }
    return PrepareStatus.partialExists;
  }

  void stopDownload() {
    cancelToken.cancel();
  }

  Future mergeTemp({required DownloadFailed fallback}) async {
    _sendStatus(ThreadStatus.working);
    await run(futureBlock: () async {
      partialFile = File(partPartialFileName);
      if (!partialFile!.existsSync()) partialFile!.createSync(recursive: true);
      final ioSink = partialFile!.openWrite(mode: FileMode.writeOnlyAppend);
      final f = File(partTempFileName);
      await ioSink.addStream(f.openRead());
      await ioSink.flush();
      await ioSink.close();
      try {
        await f.delete();
      } catch (e) {
        HyperLog.log('e');
      }
    }, fallback: (e) {
      final msg = 'sub thread: $index, mergeTemp failed with exception: $e';
      fallback(msg);
    });
  }

  Future renameFile({required DownloadFailed failed}) async {
    await run(
      futureBlock: () async {
        await partialFile?.rename(partFileName);
      },
      fallback: (e) {
        failed('$e');
      },
    );
  }
}
