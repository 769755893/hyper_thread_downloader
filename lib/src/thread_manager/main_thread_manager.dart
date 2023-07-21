import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:hyper_thread_downloader/src/base/task.dart';
import 'package:hyper_thread_downloader/src/interface/hyper_interface.dart';
import 'package:hyper_thread_downloader/src/model/thread_status.dart';
import 'package:hyper_thread_downloader/src/thread_manager/sub_thread_manager.dart';
import 'package:hyper_thread_downloader/src/util/string_util.dart';

import '../model/chunk_model.dart';
import '../model/download_info.dart';
import '../thread/thread.dart';
import '../util/log_util.dart';
import '../util/speed_manager.dart';

class MainThreadManager with Task {
  late DownloadFailed downloadFailed;
  late DownloadingLog downloadingLog;
  late DownloadComplete downloadComplete;
  late SpeedManager speedManager;
  late List<ThreadStatus> threadsStatus;
  late Completer completer;
  late Completer? prepareCompleter;
  late List<Chunk> allChunks;
  late DownloadInfo downloadInfo;
  late WorkingMerge workingMerge;
  Map<int, SendPort> ports = {};
  Map prepareList = {};

  void setupInfo({
    required List<Chunk> allChunks,
    required DownloadComplete downloadComplete,
    required DownloadFailed downloadFailed,
    required DownloadingLog downloadingLog,
    required SpeedManager speedManager,
    required Completer completer,
    required DownloadInfo downloadInfo,
    required Completer? prepareCompleter,
    required WorkingMerge workingMerge,
  }) {
    threadsStatus =
        List.generate(allChunks.length, (index) => ThreadStatus.downloading);
    this.allChunks = allChunks;
    this.downloadComplete = downloadComplete;
    this.downloadingLog = downloadingLog;
    this.downloadFailed = downloadFailed;
    this.speedManager = speedManager;
    this.completer = completer;
    this.downloadInfo = downloadInfo;
    this.prepareCompleter = prepareCompleter;
    this.workingMerge = workingMerge;
  }

  void start() {
    prepareList = Map.fromIterables(
        List.generate(allChunks.length, (index) => index),
        List.generate(allChunks.length, (index) => false));
    for (int i = 0; i < allChunks.length; i++) {
      startChunk(
          index: i,
          url: downloadInfo.url,
          savePath: downloadInfo.savePath,
          chunk: allChunks[i]);
    }
  }

  Future startChunk({
    required int index,
    required String url,
    required String savePath,
    required Chunk chunk,
  }) async {
    final ReceivePort receivePort = ReceivePort();
    handleSubThreadMessage(
        receivePort: receivePort,
        i: index,
        url: url,
        savePath: savePath,
        chunk: chunk,
        index: index);
    await startThread(receivePort);
  }

  void subComplete(int index) {
    prepareList[index] = true;
    threadsStatus[index] = ThreadStatus.downloadComplete;
    pickAllChild(status: ThreadStatus.downloadComplete);
  }

  void subFailed({required int index, required String reason}) {
    HyperLog.log('sub thread: $index failed with $reason');
    threadsStatus[index] = ThreadStatus.downloadFailed;
    pickAllChild(reason: reason, status: ThreadStatus.downloadFailed);
  }

  bool allComplete() {
    bool ret = true;
    for (final t in threadsStatus) {
      if (t != ThreadStatus.downloadComplete) {
        ret = false;
        break;
      }
    }
    return ret;
  }

  bool allFailed() {
    bool ret = true;
    for (final t in threadsStatus) {
      if (t != ThreadStatus.downloadFailed) {
        ret = false;
        break;
      }
    }
    return ret;
  }

  Future cleanFailedFiles({String? endWidth}) async {
    try {
      final baseFolder =
          downloadInfo.savePath.dropLastWhile(Platform.pathSeparator);
      final dir = Directory(baseFolder);
      final entry = dir.listSync();
      for (final f in entry) {
        if (endWidth != null) {
          if (f.path.contains('ipsw') && f.path.endsWith(endWidth)) {
            await f.delete();
          }
          continue;
        }
        if (f.path.contains('ipsw')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  Future pickAllChild(
      {String reason = '', required ThreadStatus status}) async {
    HyperLog.log(threadsStatus);
    if (allComplete()) {
      bool err = false;
      workingMerge(false);
      await mergeSub(fallback: (e) {
        err = true;
        downloadFailed(e);
      });
      await rename(failed: (e) {
        err = true;
        downloadFailed(e);
      });
      workingMerge(true);
      if (!err) {
        HyperLog.log('download complete');
        downloadComplete();
      }
      completer.complete();
      return;
    }

    if (allFailed()) {
      HyperLog.log('all failed start clean files');
      await cleanFailedFiles();
      downloadFailed('subThread all failed with reason: $reason');
      completer.complete();
      return;
    }

    if (status != ThreadStatus.downloadFailed) {
      bool existsWorking =
          threadsStatus.any((element) => element == ThreadStatus.working);
      if (existsWorking) return;
    }

    if (reason.contains('SocketException')) return;

    /// part failed.
    List<int> failedIndex = findFailedThread();
    if (failedIndex.isEmpty) return;
    rebootThread(failedIndex);
  }

  Future rebootThread(List<int> index) async {
    HyperLog.log('rebootThread: $index');
    for (int i = 0; i < index.length; i++) {
      await cleanFailedFiles(endWidth: '${index[i]}');
    }
    await Future.delayed(Duration(seconds: 1));
    prepareList = Map.fromIterables(
        List.generate(index.length, (i) => index[i]),
        List.generate(index.length, (index) => false));
    for (final i in index) {
      startChunk(
          index: i,
          url: downloadInfo.url,
          savePath: downloadInfo.savePath,
          chunk: allChunks[i]);
    }
  }

  void stopAllThread() {
    for (final port in ports.values) {
      port.send('stop');
    }
  }

  List<int> findFailedThread() {
    List<int> ret = [];
    for (int i = 0; i < threadsStatus.length; i++) {
      if (threadsStatus[i] == ThreadStatus.downloadFailed) {
        ret.add(i);
        threadsStatus[i] = ThreadStatus.working;
      }
    }
    return ret;
  }

  Future rename({required DownloadFailed failed}) async {
    await run(futureBlock: () async {
      final f = File('${downloadInfo.savePath}.0');
      await f.rename(downloadInfo.savePath);
    }, fallback: (e) {
      failed('$e');
    });
  }

  Future mergeSub({required DownloadFailed fallback}) async {
    HyperLog.log('merge sub start');
    final ReceivePort receivePort = ReceivePort();
    final Completer completer = Completer();
    receivePort.listen((message) {
      if (message is SendPort) {
        message.send(
            {'savePath': downloadInfo.savePath, 'size': allChunks.length});
      } else if (message is Map) {
        final status = ThreadStatus.fromValue(message['status']);
        switch (status) {
          case ThreadStatus.downloadComplete:
            completer.complete();
            break;
          case ThreadStatus.downloadFailed:
            final value = message['value'];
            fallback(value);
            completer.complete();
            break;
          default:
            break;
        }
      }
    });
    Isolate.spawn((sendPort) {
      final ReceivePort subPort = ReceivePort();
      subPort.listen((message) async {
        if (message is Map) {
          final savePath = message['savePath'];
          final size = message['size'];
          mergeThreadFunc(savePath: savePath, sendPort: sendPort, size: size);
          // mergeMultiThread(savePath: savePath, sendPort: sendPort);
        }
      });
      sendPort.send(subPort.sendPort);
    }, receivePort.sendPort);
    await completer.future;
  }

  Future startThread(ReceivePort receivePort) async {
    await Isolate.spawn((sendPort) {
      final subPort = ReceivePort();
      final threadManager = SubThreadManager();
      subPort.listen((message) async {
        if (message is Map) {
          await handleMainIsolate(
              threadManager: threadManager,
              message: message,
              sendPort: sendPort);
        } else if (message is String) {
          handleMainIsolateControl(
              threadManager: threadManager, message: message);
        }
      });
      sendPort.send(subPort.sendPort);
    }, receivePort.sendPort);
  }

  void sendStartMessage({
    required SendPort subPort,
    required int index,
    required String url,
    required String savePath,
    required Chunk chunk,
  }) {
    subPort.send({
      'index': index,
      'url': url,
      'savePath': savePath,
      'start': chunk.start,
      'end': chunk.end,
    });
  }

  void handleSubThreadMessage({
    required ReceivePort receivePort,
    required int i,
    required String url,
    required String savePath,
    required Chunk chunk,
    required int index,
  }) {
    receivePort.listen((message) {
      if (message is SendPort) {
        ports[index] = message;
        sendStartMessage(
            subPort: message,
            index: i,
            url: url,
            savePath: savePath,
            chunk: chunk);
        return;
      }
      if (message is Map) {
        final status = ThreadStatus.fromValue(message['status']);
        final index = message['index'];
        final value = message['value'];
        switch (status) {
          case ThreadStatus.downloading:
            mapToSpeed(message, index);
            break;
          case ThreadStatus.working:
            break;
          case ThreadStatus.downloadComplete:
            subComplete(index);
            ports.remove(index);
            speedManager.updateChunkComplete(index);
            break;
          case ThreadStatus.downloadFailed:
            subFailed(index: index, reason: value ?? '');
            downloadingLog('sub thread failed, rebooting, reason: $value');
            ports.remove(index);
            break;
          default:
            break;
        }
      }
    });
  }

  bool initPrepare = true;
  void mapToSpeed(Map message, int index) {
    if (initPrepare) {
      prepareList[index] = true;
      checkAllPrepare();
    }
    int cur = message['cur'];
    int total = message['total'];
    speedManager.updateSpeed(index, cur, total);
  }

  void checkAllPrepare() {
    bool ret = true;
    for (final f in prepareList.values) {
      if (!f) {
        ret = false;
        break;
      }
    }
    if (ret) {
      initPrepare = false;
      prepareCompleter?.complete();
    }
  }
}
