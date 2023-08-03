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
  late Chunks _chunks;
  final Dio _dio = Dio();
  int _total = 0;
  int _id = 0;
  MainThreadManager? _mainThreadManager;
  Completer? _prepareCompleter;
  Completer? _cancelCompleter;

  Future? get _prepareWork => _prepareCompleter?.future;

  Future? get _cancelWork => _cancelCompleter?.future;

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
    _id = taskStart(url: url);
    if (_id == -1) {
      downloadTaskId(_id);
      HyperLog.log('taskId -1 return: ${taskMap.values}');
      return false;
    }
    downloadTaskId(_id);
    return true;
  }

  @override
  Future setupWaiting(PrepareWorking prepareWorking) async {
    prepareWorking(false);
    if (_prepareCompleter?.isCompleted == false) {
      await _prepareWork;
    }
    if (_cancelCompleter?.isCompleted == false) {
      await _cancelWork;
    }
    _mainThreadManager = MainThreadManager();
    _prepareCompleter = Completer();
    _cancelCompleter = Completer();
    _prepareCompleter?.future.then((value) {
      prepareWorking(true);
    });
  }

  @override
  Future<bool> chunksInit({
    required String url,
    required int threadCount,
    required DownloadFailed downloadFailed,
    required int? fileSize,
  }) async {
    bool ret = true;
    await chunkSizeInit(
      url: url,
      threadCount: threadCount,
      fallback: (Object e) {
        _prepareCompleter?.complete();
        downloadFailed('chunk init failed with: $e');
        ret = false;
      },
      fileSize: fileSize,
    );
    return ret;
  }

  ///
  /// in almost case, you just only use these two interface for enough.
  /// one is startDownload
  /// two is stopDownload
  ///
  /// @params
  /// url: the download url
  /// savePath: your save path , the path should contains your save file name.
  /// threadCount: the count you want to start thread count, recommend it should be less than cpu count.
  /// fileSize: the fileSize, just for the another safety if the fileSize get filed, so if you already has fileSize, just put it on.
  /// prepareWorking: the prepare working process callback, for the init process, and resume process, you can do that progress dialog to control user behavior.
  /// workingMerge: the merge thread start merge the part file process, you also can do that progress dialog when this callback called.
  /// downloadComplete: not need to mentioned.
  /// downloadFailed: not need to mentioned.
  /// downloadTaskId: the task id you start about current download task, not yet support multi task in single instance. so the only work is to stop download using it.
  /// downloadingLog: the log for sub thread failed or other etc.
  @override
  Future startDownload({
    required String url,
    required String savePath,
    required int threadCount,
    int? fileSize,
    required PrepareWorking prepareWorking,
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
    await setupWaiting(prepareWorking);
    if (!(await chunksInit(url: url, threadCount: threadCount, downloadFailed: downloadFailed, fileSize: fileSize))) {
      return;
    }
    start(
      downloadProgress: downloadProgress,
      downloadFailed: downloadFailed,
      downloadComplete: downloadComplete,
      url: url,
      savePath: savePath,
      workingMerge: workingMerge,
      downloadingLog: downloadingLog,
    );
  }

  @override
  void start({
    required DownloadSpeedProgress downloadProgress,
    required DownloadFailed downloadFailed,
    required DownloadComplete downloadComplete,
    required String url,
    required String savePath,
    required WorkingMerge workingMerge,
    required DownloadingLog downloadingLog,
  }) {
    final allChunks = _chunks.allChunks;
    final speedManager = SpeedManager(
      chunks: allChunks,
      downloadSpeedProgress: downloadProgress,
      size: allChunks.length,
      total: _total,
    );
    _mainThreadManager?.setupInfo(
      downloadFailed: (String reason) {
        HyperLog.log('download failed: $reason');
        downloadFailed(reason);
      },
      speedManager: speedManager,
      downloadComplete: downloadComplete,
      allChunks: allChunks,
      downloadInfo: DownloadInfo(url: url, savePath: savePath),
      prepareCompleter: _prepareCompleter,
      cancelCompleter: _cancelCompleter,
      workingMerge: workingMerge,
      downloadingLog: downloadingLog,
    );
    _mainThreadManager?.start();
  }

  @override
  Future chunkSizeInit({
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

    _total = ret;
    _chunks = Chunks(total: _total, chunks: threadCount);
  }

  Future<int?> fileLength({
    required String url,
    required Function(Object e) fallback,
  }) async {
    int? ret;
    await run(futureBlock: () async {
      final res = await _dio.headUri(Uri.parse(url));
      ret = int.parse(res.headers.value(HttpHeaders.contentLengthHeader)!);
    }, fallback: (e) {
      print(e);
      fallback(e);
    });
    return ret;
  }

  /// the interface for stop current download task with task id.
  /// when you need resume the next, just call the startDownload again.
  @override
  void stopDownload({required int id}) {
    HyperLog.log('stop task id: $id');
    taskEnd(id: id);
    HyperLog.log('task end: ${taskMap.values}');
    _mainThreadManager?.stopAllThread();
  }
}
