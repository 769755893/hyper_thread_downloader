@Timeout(Duration(hours: 1))

import 'hyper_thread_entry.dart';
import 'package:test/scaffolding.dart';


void main() async {
  test('basic test', () async => await testEntry());
}
