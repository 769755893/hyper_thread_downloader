enum ThreadStatus {
  downloading(0),
  downloadFailed(1),
  downloadComplete(2),
  working(3);

  const ThreadStatus(this.value);

  final int value;

  static ThreadStatus fromValue(int v) =>
      ThreadStatus.values.firstWhere((element) => element.value == v);
}
