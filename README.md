
## Features

A Simple Multi Thread Downloader with Dio package by dart code.

## Getting started

```dart
    final md = HyperDownload();
    int taskId = -1;
    final url =
        'https://updates.cdn-apple.com/2023WinterFCS/fullrestores/032-73564/23D75440-B300-4932-8BD7-283C6218FF4E/iPhone_4.7_15.7.6_19H349_Restore.ipsw';
    await md.startDownload(
    url: url,
    savePath: 'C:\\Users\\Administrator\\Desktop\\iPhone_5.5_P3_15.7.6_19H349_Restore.ipsw',
    threadCount: Platform.numberOfProcessors,
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
    workingMerge: (bool ret) {});
    # this workingMerge callback is been called when merge thread start.
```

## Usage

#Add dependency

This packages is totally use dart code, so just add dependency.
```yaml
dependencies:
  flutter:
    sdk: flutter
  # add flutter_screenutil
  hyper_thread_downloader: ^{latest version}
```

## Additional information

If has any problem , please create an issue in github.
