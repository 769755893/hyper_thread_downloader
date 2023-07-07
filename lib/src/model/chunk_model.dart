class Chunks {
  final int total;
  final int chunks;

  Chunks({required this.total, required this.chunks});

  int get _per => total ~/ chunks;

  int get _left => total - _per * (chunks - 1);

  int _start(int index) {
    return _per * index;
  }

  int _end(int index, int left, bool last) {
    return last ? _per * (index) + left - 1 : _per * (index + 1) - 1;
  }

  List<Chunk> get allChunks {
    List<Chunk> ret = [];
    for (int i = 0; i < chunks; i++) {
      ret.add(_indexChunkSize(i, i == chunks - 1));
    }
    return ret;
  }

  Chunk _indexChunkSize(int index, bool last) {
    return Chunk(start: _start(index), end: _end(index, _left, last));
  }
}

class Chunk {
  int start;
  int end;

  Chunk({required this.start, required this.end});
}
