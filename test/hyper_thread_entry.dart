import 'dart:async';
import 'dart:io';

import 'package:hyper_thread_downloader/hyper_thread_downloader.dart';
import 'package:hyper_thread_downloader/src/util/string_util.dart';

Future testEntry() async {
  final completer = Completer();
  final md = HyperDownload();
  final baseDir = '/Volumes/Macintosh-TB/download';
  int taskId = -1;
  final url =
      'https://updates.cdn-apple.com/2023WinterFCS/fullrestores/032-73564/23D75440-B300-4932-8BD7-283C6218FF4E/iPhone_4.7_15.7.6_19H349_Restore.ipsw';
  await md.startDownload(
      url: url,
      savePath: '$baseDir/${url.getDropLastWhile('/')}',
      threadCount: Platform.numberOfProcessors,
      downloadProgress: ({
        required double progress,
        required double speed,
        required double remainTime,
        required int count,
        required int total,
      }) {},
      downloadComplete: () {
        completer.complete();
      },
      downloadFailed: (String reason) {
        completer.complete();
      },
      downloadTaskId: (int id) {
        print('start task id: $id');
        taskId = id;
      },
      workingMerge: (bool ret) {},
      downloadingLog: (String log) {},
      prepareWorking: (bool value) {});

  stdin.listen(
        (event) {
      String e = String.fromCharCodes(event);
      if (e.contains('stop')) {
        md.stopDownload(id: taskId);
      } else if (e.contains('start')) {
        md.startDownload(
          url: url,
          savePath: '$baseDir/${url.getDropLastWhile('/')}',
          threadCount: 5,
          downloadProgress: ({
            required double progress,
            required double speed,
            required double remainTime,
            required int count,
            required int total,
          }) {},
          downloadComplete: () {},
          downloadFailed: (String reason) {},
          downloadTaskId: (int id) {
            print('start task id: $id');
            taskId = id;
          },
          workingMerge: (bool ret) {},
          downloadingLog: (String log) {},
          prepareWorking: (bool value) {},
        );
      }
    },
  );
  await completer.future;
}