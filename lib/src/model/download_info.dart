import 'package:hyper_thread_downloader/src/util/string_util.dart';

class DownloadInfo {
  final String url;
  final String savePath;
  String get fileName => url.getDropLastWhile('/');

  DownloadInfo({
    required this.url,
    required this.savePath,
  });
}