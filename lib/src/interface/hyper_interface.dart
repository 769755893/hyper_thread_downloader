typedef DownloadSpeedProgress = void Function({
  required double progress,
  required double speed,
  required double remainTime,
  required int count,
  required int total,
});

typedef DownloadComplete = void Function();
typedef WorkingMerge = void Function(bool done);
typedef DownloadFailed = void Function(String reason);
typedef DownloadingLog = void Function(String log);
typedef DownloadTaskId = void Function(int id);
typedef PrepareWorking = void Function(bool done);

abstract class HyperInterface {
  void startDownload({
    required String url,
    required String savePath,
    required int threadCount,
    required PrepareWorking prepareWorking,
    required WorkingMerge workingMerge,
    required DownloadSpeedProgress downloadProgress,
    required DownloadComplete downloadComplete,
    required DownloadFailed downloadFailed,
    required DownloadTaskId downloadTaskId,
    required DownloadingLog downloadingLog,
  });

  void stopDownload({required int id});

  Future<bool> chunksInit({
    required String url,
    required int threadCount,
    required DownloadFailed downloadFailed,
    required int? fileSize,
  });

  Future setupWaiting(PrepareWorking prepareWorking);

  void start({
    required DownloadSpeedProgress downloadProgress,
    required DownloadFailed downloadFailed,
    required DownloadComplete downloadComplete,
    required String url,
    required String savePath,
    required WorkingMerge workingMerge,
    required DownloadingLog downloadingLog,
  });

  Future chunkSizeInit({
    required String url,
    required int threadCount,
    required Function(Object e) fallback,
    int? fileSize,
  });

  Map taskMap = {};
  int taskId = 0;

  int taskStart({required String url}) {
    final values = taskMap.values;
    if (values.contains(url)) {
      return -1;
    }
    taskMap.addAll({
      taskId: url,
    });
    taskId++;
    return taskId - 1;
  }

  void taskEnd({required int id}) {
    taskMap.remove(id);
  }
}
