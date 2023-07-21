import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:hyper_thread_downloader/src/util/log_util.dart';

class MergeBlock {
  String sourcePath;
  String targetPath;

  MergeBlock({required this.sourcePath, required this.targetPath});
}

enum MergeThreadStatus {
  merging(0),
  complete(1),
  failed(2),
  ;

  final int value;

  const MergeThreadStatus(this.value);

  static MergeThreadStatus fromValue(int value) =>
      MergeThreadStatus.values.firstWhere((element) => element.value == value);
}

class MergeThread {
  final List<MergeBlock> blocks;
  List<MergeThreadStatus> status = [];
  final Function() complete;
  final Function(String reason) failed;

  MergeThread({
    required this.blocks,
    required this.complete,
    required this.failed,
  }) {
    status = List.generate(blocks.length, (index) => MergeThreadStatus.merging);
  }

  void start() {
    for (int i = 0; i < blocks.length; i++) {
      startMergeThread(blocks[i], i);
    }
  }

  void startMergeThread(MergeBlock block, int index) {
    ReceivePort receivePort = ReceivePort();
    receivePort.listen((port) {
      if (port is SendPort) {
        port.send({
          'sourcePath': block.sourcePath,
          'targetPath': block.targetPath,
          'index': index,
        });
      } else if (port is Map) {
        handleSubMessage(port);
      }
    });
    Isolate.spawn((port) {
      final subPort = ReceivePort();
      subPort.listen((subMessage) {
        if (subMessage is Map) {
          final block = MergeBlock(
              sourcePath: subMessage['sourcePath'],
              targetPath: subMessage['targetPath']);
          final index = subMessage['index'];
          startMerge(block, port, index);
        }
      });
      port.send(subPort.sendPort);
    }, receivePort.sendPort);
  }

  List<String> failedReason = [];

  void handleSubMessage(Map message) {
    final s = MergeThreadStatus.fromValue(message['status']);
    final index = message['index'] as int;
    final value = message['value'];
    switch (s) {
      case MergeThreadStatus.merging:
        status[index] = MergeThreadStatus.merging;
        pickChildren();
        break;
      case MergeThreadStatus.failed:
        failedReason.add(value);
        status[index] = MergeThreadStatus.failed;
        pickChildren();
        break;
      case MergeThreadStatus.complete:
        status[index] = MergeThreadStatus.complete;
        pickChildren();
        break;
      default:
        break;
    }
  }

  bool get allComplete {
    bool ret = true;
    for (final s in status) {
      if (s != MergeThreadStatus.complete && s != MergeThreadStatus.failed) {
        ret = false;
        break;
      }
    }
    return ret;
  }

  void pickChildren() {
    if (allComplete) {
      if (failedReason.isNotEmpty) {
        failed(failedReason.join(','));
        return;
      }
      complete();
    }
  }
}

Future startMerge(MergeBlock block, SendPort port, int index) async {
  final sourceFile = File(block.sourcePath);
  final targetFile = File(block.targetPath);
  if (!sourceFile.existsSync() || !targetFile.existsSync()) {
    port.send({
      'status': MergeThreadStatus.failed.value,
      'index': index,
      'value': 'sourceFile or targetFile not exists',
    });
    return;
  }
  HyperLog.log(
      'start MergeThread:\nindex: $index, source: ${block.sourcePath} - target: ${block.targetPath}');
  final ioSink = sourceFile.openWrite(mode: FileMode.writeOnlyAppend);
  HyperLog.log('index: $index,open write done');
  await ioSink.addStream(targetFile.openRead());
  HyperLog.log('index: $index,add stream done');
  HyperLog.log('index: $index,flush done');
  await ioSink.close();
  HyperLog.log('index: $index,close done');
  await targetFile.delete();
  HyperLog.log('index: $index,delete done');
  HyperLog.log('index: $index,merge thread: $index merge Complete');
  Isolate.exit(port, {
    'status': MergeThreadStatus.complete.value,
    'index': index,
  });
}
