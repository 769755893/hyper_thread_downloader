mixin Task {
  Future run({required Future Function() futureBlock, required Function(Object reason) fallback}) async {
    try {
      await futureBlock();
    } catch (e) {
      fallback(e);
    }
  }
}
