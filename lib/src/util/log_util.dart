enum HyperLogLevel {
  open,
  close,
  all,
}
class HyperLog {
  HyperLog._internal();

  static HyperLogLevel _logLevel = HyperLogLevel.open;

  static void openLog(HyperLogLevel level) {
    _logLevel = level;
  }

  static void log(Object e) {
    if (_logLevel == HyperLogLevel.close) return;
    print('$e');
  }
}