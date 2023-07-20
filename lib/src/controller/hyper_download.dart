import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hyper_thread_downloader/src/model/chunk_model.dart';
import 'package:hyper_thread_downloader/src/model/download_info.dart';
import 'package:hyper_thread_downloader/src/thread_manager/main_thread_manager.dart';
import 'package:hyper_thread_downloader/src/util/log_util.dart';
import 'package:hyper_thread_downloader/src/util/string_util.dart';

import '../base/task.dart';
import '../interface/hyper_interface.dart';
import '../util/speed_manager.dart';

//TODO thread merge speed up
//TODO thread guard when weak network.
class HyperDownload extends HyperInterface with Task {
  late Chunks chunks;
  final Dio dio = Dio();
  int total = 0;
  int id = 0;
  MainThreadManager? _mainThreadManager;
  Completer? _prepare;

  Future? get prepareWork => _prepare?.future;

  bool pass({
    required String savePath,
    required DownloadComplete downloadComplete,
    required String url,
    required DownloadFailed downloadFailed,
    required DownloadTaskId downloadTaskId,
  }) {
    final f = File(savePath);
    if (f.existsSync()) {
      HyperLog.log('file exists download complete');
      downloadComplete();
      return false;
    }
    if (url.isEmpty) {
      downloadFailed('download url is empty');
      return false;
    }
    id = taskStart(url: url);
    if (id == -1) {
      downloadTaskId(id);
      HyperLog.log('taskId -1 return: ${taskMap.values}');
      return false;
    }
    return true;
  }

  @override
  Future startDownload({
    required String url,
    required String savePath,
    required int threadCount,
    int? fileSize,
    required WorkingMerge workingMerge,
    required DownloadSpeedProgress downloadProgress,
    required DownloadComplete downloadComplete,
    required DownloadFailed downloadFailed,
    required DownloadTaskId downloadTaskId,
    required DownloadingLog downloadingLog,
  }) async {
    final fileName = url.getDropLastWhile('/');
    if (savePath.endsWith(Platform.pathSeparator)) {
      savePath = '$savePath$fileName';
    }
    HyperLog.log('startDownload');
    if (!pass(
      savePath: savePath,
      downloadComplete: downloadComplete,
      url: url,
      downloadFailed: downloadFailed,
      downloadTaskId: downloadTaskId,
    )) return;
    _mainThreadManager = MainThreadManager();
    _prepare = Completer();
    downloadTaskId(id);
    bool chunkFailed = false;
    await initChunk(
      url: url,
      threadCount: threadCount,
      fallback: (Object e) {
        _prepare?.complete();
        downloadFailed('chunk init failed with: $e');
        chunkFailed = true;
      },
      fileSize: fileSize,
    );
    if (chunkFailed) return;

    final allChunks = chunks.allChunks;
    final speedManager = SpeedManager(
      chunks: allChunks,
      downloadSpeedProgress: downloadProgress,
      size: allChunks.length,
      total: total,
    );
    _mainThreadManager?.setupInfo(
      downloadFailed: (String reason) {
        HyperLog.log('download failed: $reason');
        downloadFailed(reason);
      },
      speedManager: speedManager,
      completer: Completer(),
      downloadComplete: downloadComplete,
      allChunks: allChunks,
      downloadInfo: DownloadInfo(url: url, savePath: savePath),
      prepareCompleter: _prepare,
      workingMerge: workingMerge,
      downloadingLog: downloadingLog,
    );
    _mainThreadManager?.start();
  }

  Future initChunk({
    required String url,
    required int threadCount,
    required Function(Object e) fallback,
    int? fileSize,
  }) async {
    Object tempFallback = '';

    final ret = await fileLength(
            url: url,
            fallback: (e) {
              tempFallback = e;
            }) ??
        fileSize;

    if (ret == null) {
      fallback(tempFallback);
      return;
    }

    total = ret;
    chunks = Chunks(total: total, chunks: threadCount);
  }

  Future<int?> fileLength({
    required String url,
    required Function(Object e) fallback,
  }) async {
    int? ret;
    await run(futureBlock: () async {
      final res = await dio.headUri(Uri.parse(url));
      ret = int.parse(res.headers.value(HttpHeaders.contentLengthHeader)!);
    }, fallback: (e) {
      print(e);
      fallback(e);
    });
    return ret;
  }

  @override
  void stopDownload({required int id}) {
    HyperLog.log('stop task id: $id');
    taskEnd(id: id);
    HyperLog.log('task end: ${taskMap.values}');
    _mainThreadManager?.stopAllThread();
  }
}
