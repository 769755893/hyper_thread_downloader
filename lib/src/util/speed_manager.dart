import 'package:hyper_thread_downloader/src/model/chunk_model.dart';
import 'package:hyper_thread_downloader/src/util/string_util.dart';

import '../interface/hyper_interface.dart';
import 'clock_util.dart';

class Speed {
  double progress = 0;
  double downloadSpeed = 0;
  double remainTime = 0.0;
  int lastCalculateCount = 0;
  int lastClock = 0;
  int cur = 0;
  int total = 0;
}

extension SpeedExt on List<Speed> {
  double get progress => fold(0, (previousValue, element) => previousValue + element.progress / length.toDouble());

  double get downloadSpeed => fold(0, (previousValue, element) => previousValue + element.downloadSpeed);

  double get remainTime => fold(0, (previousValue, element) => previousValue + element.remainTime / length.toDouble());

  int get lastCalculateCount => fold(0, (previousValue, element) => previousValue + element.lastCalculateCount);

  int get lastClock => fold(0, (previousValue, element) => previousValue + element.lastClock);

  int get cur => fold(0, (previousValue, element) => previousValue + element.cur);

  int get total => fold(0, (previousValue, element) => previousValue + element.total);
}

class SpeedManager {
  int size;
  List<Chunk> chunks;
  late List<Speed> speeds;
  final DownloadSpeedProgress downloadSpeedProgress;
  int total;

  SpeedManager({
    required this.chunks,
    required this.size,
    required this.downloadSpeedProgress,
    required this.total,
  }) {
    speeds = List.generate(size, (index) => Speed());
  }

  void updateChunkComplete(int index) {
    speeds[index].total = chunks[index].end - chunks[index].start;
    speeds[index].cur = speeds[index].total;
    speeds[index].remainTime = 0;
    speeds[index].progress = 1;
  }

  void updateSpeed(int index, int count, int total) {
    double progress = count.toDouble() / total.toDouble();
    int recordClock = clock;
    if (speeds[index].downloadSpeed <= 0) {
      speeds[index].downloadSpeed = (count - speeds[index].lastCalculateCount).toDouble() /
          (recordClock - speeds[index].lastClock).toDouble() *
          clockStep;
    } else {
      int diff = recordClock - speeds[index].lastClock;
      if (diff > 2 * clockStep) {
        speeds[index].downloadSpeed =
            (count - speeds[index].lastCalculateCount).toDouble() / diff.toDouble() * clockStep;
        speeds[index].lastClock = recordClock;
        speeds[index].lastCalculateCount = count;
      }
    }
    int remainBytes = total - count;
    if (speeds[index].downloadSpeed <= 0) {
      speeds[index].downloadSpeed = 1;
    }
    speeds[index].remainTime = remainBytes.toDouble() / speeds[index].downloadSpeed;
    speeds[index].progress = progress;
    speeds[index].cur = count;
    speeds[index].total = total;
    updateTotalSpeed();
  }

  int lastUpdateClock = clock;

  void updateTotalSpeed() {
    int currentClock = clock;
    if (currentClock - lastUpdateClock < 0.5 * clockStep) return;
    lastUpdateClock = currentClock;
    downloadSpeedProgress(
      progress: speeds.progress,
      speed: speeds.downloadSpeed,
      remainTime: getLeftHour(speeds.remainTime) > 24 ? 3600 * 24 : speeds.remainTime,
      count: speeds.cur,
      total: total,
    );
  }
}
