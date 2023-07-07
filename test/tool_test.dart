import 'package:hyper_thread_downloader/src/thread/thread.dart';
import 'package:test/scaffolding.dart';

void main() {
  group(
    'tools',
    () => {
      test('block tool', () {
        final blocks = findBlocks("D:\\iPhone_4.7_15.7.6_19H349_Restore.ipsw");
        for (final block in blocks) {
          print('${block.sourcePath} - ${block.targetPath}');
        }
      }),
    },
  );
}
