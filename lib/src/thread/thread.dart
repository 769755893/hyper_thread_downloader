import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:hyper_thread_downloader/src/thread_manager/sub_thread_manager.dart';
import 'package:hyper_thread_downloader/src/util/merge_util/merge_block.dart';
import 'package:hyper_thread_downloader/src/util/string_util.dart';

import '../model/thread_status.dart';
import '../util/log_util.dart';

/// note that the thread start entry must be global static.

void handleMainIsolateControl({
  required SubThreadManager threadManager,
  required String message,
}) {
  if (message == 'stop') {
    threadManager.stopDownload();
  }
}

Future handleMainIsolate({
  required SubThreadManager threadManager,
  required Map message,
  required SendPort sendPort,
}) async {
  String url = message['url'];
  String savePath = message['savePath'];
  int index = message['index'];
  int start = message['start'];
  int end = message['end'];
  await threadManager.startDownload(
    url: url,
    savePath: savePath,
    index: index,
    start: start,
    end: end,
    sendPort: sendPort,
  );
}

Future mergeThreadFunc({required String savePath, required int size, required SendPort sendPort}) async {
  List<Completer> completers = List.generate(size, (index) => Completer());
  try {
    final ioSink = File('$savePath.0').openWrite(mode: FileMode.writeOnlyAppend);
    for (int i = 1; i < size; i++) {
      final t = File('$savePath.$i');
      await ioSink.addStream(t.openRead());
      Future.delayed(Duration(seconds: 1), () async {
        await t.delete();
        completers[i].complete();
      });
    }
    await ioSink.flush();
    await ioSink.close();
  } catch (e) {
    final msg = 'merge all sub failed with exception: $e';
    HyperLog.log(msg);
    Isolate.exit(sendPort, {
      'status': ThreadStatus.downloadFailed.value,
      'value': msg,
    });
  }
  for (int i = 1; i < completers.length; i++) {
    await completers[i].future;
  }
  Isolate.exit(sendPort, {'status': ThreadStatus.downloadComplete.value});
}

bool pathContainsFile(String basePath) {
  final dir = Directory(basePath);
  if (!dir.existsSync()) return false;
  final entry = dir.listSync().map((e) => e.path.endWithNumber()).where((element) => element);
  HyperLog.log('check path contains length: ${entry.length}');
  return entry.length > 1;
}

Future mergeMultiThread({required String savePath, required SendPort sendPort}) async {
  final basePath = savePath.dropLastWhile(Platform.pathSeparator);
  while (pathContainsFile(basePath)) {
    final List<MergeBlock> blocks = findBlocks(basePath);
    final completer = Completer();
    MergeThread mergeThread = MergeThread(
      blocks: blocks,
      complete: () {
        completer.complete();
      },
      failed: (String reason) {
        completer.complete();
      },
    );
    mergeThread.start();
    await completer.future;
  }
  HyperLog.log('all merge done');
  Isolate.exit(sendPort, {
    'status': ThreadStatus.downloadComplete.value,
  });
}

List<MergeBlock> findBlocks(String savePath) {
  final path = findPath(savePath);
  List<MergeBlock> blocks = [];
  for (int i = 0; i < path.length - 1; i += 2) {
    blocks.add(MergeBlock(sourcePath: path[i], targetPath: path[i + 1]));
  }
  return blocks;
}

List<String> findPath(String basePath) {
  final dir = Directory(basePath);
  if (!dir.existsSync()) return [];
  final entry = dir.listSync();
  List<String> path = [];
  for (final f in entry) {
    final p = f.path;
    if (p.endWithNumber()) {
      HyperLog.log('find: $p');
      path.add(p);
    }
  }
  path.sort((a, b) => int.parse(a.split('.').last).compareTo(int.parse(b.split('.').last)));
  return path;
}
