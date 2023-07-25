import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:hyper_thread_downloader/src/base/task.dart';
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

  String get partTempFileName => '$savePath$partialExtension$tempExtension.$index';

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

  void sendStatus({required ThreadStatus status, required bool exit, dynamic basicType}) {
    if (exit) {
      Isolate.exit(sendPort, {'status': status.value, 'index': index, 'value': basicType});
    }
    sendPort.send({
      'status': status.value,
      'index': index,
      'value': basicType,
    });
  }

  Future startDownload() async {
    sendStatus(status: ThreadStatus.downloading, exit: false);
    dio = Dio()..options = BaseOptions(connectTimeout: Duration(seconds: 5));
    cancelToken = CancelToken();
    PrepareStatus status = await downloadPrepare();
    switch (status) {
      case PrepareStatus.partDone:
        HyperLog.log('find complete sub part, sub thread: $index download complete');
        sendStatus(status: ThreadStatus.downloadComplete, exit: true);
        break;
      case PrepareStatus.partialExists:
        partialFileLength = partialFile?.lengthSync() ?? 0;
        print('partialFileLength: $partialFileLength');
        try {
          final res = await dio.download(
            url,
            partTempFileName,
            onReceiveProgress: (int cur, int total) => sendStatus(
                status: ThreadStatus.downloading,
                basicType: {
                  'cur': cur + partialFileLength,
                  'total': total + partialFileLength,
                },
                exit: false),
            options: Options(headers: {HttpHeaders.rangeHeader: 'bytes=${start + partialFileLength}-$end'}),
            cancelToken: cancelToken,
            deleteOnError: false,
          );
          await Future.delayed(Duration(seconds: 2));
          if (res.statusCode == HttpStatus.partialContent) {
            await mergeTemp();
            await renameFile();
            sendStatus(status: ThreadStatus.downloadComplete, exit: true);
            return;
          }
          final msg = jsonEncode(
            {
              'statusCode': res.statusCode,
              'data': res.data.toString(),
            },
          );
          HyperLog.log('download failed with incomplete code: $msg');
          sendStatus(status: ThreadStatus.downloadFailed, exit: true, basicType: msg);
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            final msg = 'download cancel sub thread: $index';
            HyperLog.log(msg);
            sendStatus(status: ThreadStatus.downloadCancel, exit: true, basicType: msg);
          }
          if (e.error is SocketException) {
            HyperLog.log('download failed with socket exception');
            sendStatus(status: ThreadStatus.downloadFailed, exit: true, basicType: 'sub thread failed with socket exception: ${e.error}');
            return;
          }
          final msg = 'download failed with dio error: $e, ${e.error}';
          HyperLog.log(msg);
          sendStatus(status: ThreadStatus.downloadFailed, exit: true, basicType: msg);
        } catch (e) {
          final msg = 'download failed with unknown error: $e';
          HyperLog.log(msg);
          sendStatus(status: ThreadStatus.downloadFailed, exit: true, basicType: msg);
        }
        break;
      default:
        break;
    }
  }

  Future<PrepareStatus> downloadPrepare() async {
    final partDoneFile = File(partFileName);
    if (partDoneFile.existsSync()) return PrepareStatus.partDone;
    final tempFile = File(partTempFileName);
    if (tempFile.existsSync()) {
      await mergeTemp();
    }
    return PrepareStatus.partialExists;
  }

  void stopDownload() {
    cancelToken.cancel();
  }

  Future mergeTemp() async {
    sendStatus(status: ThreadStatus.merging, exit: false);
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
      sendStatus(status: ThreadStatus.mergeFailed, exit: true, basicType: msg);
    });
  }

  Future renameFile() async {
    await run(
      futureBlock: () async {
        await partialFile?.rename(partFileName);
      },
      fallback: (e) {
        final msg = 'sub thread: $index, renameFile failed with exception: $e';
        sendStatus(
          status: ThreadStatus.renameFailed,
          exit: true,
          basicType: msg,
        );
      },
    );
  }
}
