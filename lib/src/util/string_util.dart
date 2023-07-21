import 'dart:math';

import 'package:hyper_thread_downloader/src/util/log_util.dart';

extension StringExt on String {
  bool endWithNumber() {
    bool ret = false;
    for (int i = 0; i < 128; i++) {
      if (endsWith('$i')) {
        ret = true;
        break;
      }
    }
    return ret;
  }

  bool isIn(List<String> condition) {
    for (var i in condition) {
      if (this == i) return true;
    }
    return false;
  }

  String reverse() {
    var ans = '';
    for (var i = length - 1; i >= 0; i--) {
      ans = '$ans${this[i]}';
    }
    return ans;
  }

  /// the str return does not contains the condition str.
  String dropLastWhile(String condition) {
    var t = reverse();
    var ans = '';
    var flg = true;
    for (int i = 0; i < t.length; i++) {
      if (t[i] == condition && flg) {
        flg = false;
        continue;
      }
      if (!flg) ans = '$ans${t[i]}';
    }
    return ans.reverse();
  }

  /// the str return does not contains the condition str.

  String getDropLastWhile(String condition) {
    var t = reverse();
    var ans = '';
    var flg = true;
    for (int i = 0; i < t.length; i++) {
      if (t[i] == condition && flg) {
        flg = false;
        continue;
      }
      if (flg) ans = '$ans${t[i]}';
    }
    return ans.reverse();
  }

  String dropWhile(List<String> condition) {
    var ans = '';
    var flg = true;
    for (int i = 0; i < length; i++) {
      if (this[i].isIn(condition) && flg) {
        flg = false;
      }
      if (!flg) ans = '$ans${this[i]}';
    }
    return ans;
  }

  String getDropWhile(String condition) {
    var ans = '';
    var flg = true;
    for (int i = 0; i < length; i++) {
      if (this[i] == condition && flg) {
        flg = false;
        continue;
      }
      if (flg) ans = '$ans${this[i]}';
    }
    return ans;
  }

  String replaceStrWidth({required String before, required String next}) {
    var ans = '';
    for (int i = 0; i < length; i++) {
      if (this[i] == before) {
        ans = '$ans$next';
      } else {
        ans = '$ans${this[i]}';
      }
    }
    return ans;
  }
}

String formatFileSize(fileSize,
    {int position = 2, int scale = 1024, int specified = -1}) {
  try {
    double num = 0;
    List sizeUnit = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'YB'];
    if (fileSize is String) {
      num = double.parse(fileSize);
    } else if (fileSize is int) {
      num = fileSize * 1.0;
    } else if (fileSize is double) {
      num = fileSize;
    }
    if (num > 0) {
      int unit = log(num) ~/ log(scale);
      if (specified >= 0 && specified < sizeUnit.length) {
        unit = specified;
      }
      double size = num / pow(scale, unit);
      String numStr = formatNum(num: size, position: position);
      return '$numStr ${sizeUnit[unit]}';
    }
  } catch (e) {
    HyperLog.log(
        'formatFileSize error:$fileSize, $position, $scale, $specified, with error: $e');
  }
  return '0 B';
}

String formatNum({required double num, required int position}) {
  String numStr = num.toString();
  int dotIndex = numStr.indexOf('.');

  if (num % 1 != 0 && (numStr.length - 1 - dotIndex < position)) {
    return numStr;
  }
  int numbs = pow(10, position).toInt();

  double remainder = num * numbs % numbs;

  if (position > 0 && remainder >= 0.5) {
    return num.toStringAsFixed(position);
  }
  return num.toStringAsFixed(0);
}

int getLeftHour(double seconds) {
  return seconds ~/ 3600;
}
