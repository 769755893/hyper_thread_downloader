enum ThreadStatus {
  downloading(0),
  downloadFailed(1),
  downloadComplete(2),
  downloadCancel(3),
  merging(4),
  mergeFailed(5),
  rename(6),
  renameFailed(7),
  ;

  const ThreadStatus(this.value);

  final int value;

  static ThreadStatus fromValue(int v) =>
      ThreadStatus.values.firstWhere((element) => element.value == v);
}
