import 'dart:io';

Future<void> main() async {
  print('🧪 TESTING LOCAL INDEX QUEUE (TC-A to TC-F)');

  final queueFile = File('go2rtc/index_queue/pending_segments.json');
  if (await queueFile.exists()) {
    print('📂 Found existing queue file:');
    print(await queueFile.readAsString());
  } else {
    print('📂 No queue file found (Clean Slate)');
  }
}
