import 'package:flutter_test/flutter_test.dart';
import 'package:vigil_app/features/playback/domain/models/recording.dart';
import 'package:vigil_app/features/playback/presentation/controllers/timeline_controller.dart';

void main() {
  group('TimelineController', () {
    late TimelineController controller;
    final now = DateTime(2026, 1, 21, 12, 0, 0); // Base reference time

    final recording1 = Recording(
      id: '1',
      cameraId: 'cam1',
      cameraName: 'Front Door',
      filePath: 'segment1.mp4',
      startTime: now.add(const Duration(minutes: 0)), // 12:00
      endTime: now.add(const Duration(minutes: 10)), // 12:10
      durationSeconds: 600,
    );

    final recording2 = Recording(
      id: '2',
      cameraId: 'cam1',
      cameraName: 'Front Door',
      filePath: 'segment2.mp4',
      startTime: now.add(const Duration(minutes: 20)), // 12:20 (10 min gap)
      endTime: now.add(const Duration(minutes: 30)), // 12:30
      durationSeconds: 600,
    );

    setUp(() {
      controller = TimelineController(initialTime: now, onTimeChanged: (_) {});
      controller.setRecordings([recording1, recording2]);
    });

    test('getSeekTarget finds correct segment and offset (Start)', () {
      final target = controller.getSeekTargetFor(now); // 12:00
      expect(target, isNotNull);
      expect(target!.recording.id, '1');
      expect(target.offset, Duration.zero);
    });

    test('getSeekTarget finds correct segment and offset (Middle)', () {
      final middle = now.add(const Duration(minutes: 5)); // 12:05
      final target = controller.getSeekTargetFor(middle);
      expect(target, isNotNull);
      expect(target!.recording.id, '1');
      expect(target.offset, const Duration(minutes: 5));
    });

    test('getSeekTarget returns null for GAP (12:15)', () {
      final gapTime = now.add(
        const Duration(minutes: 15),
      ); // 12:15 (Between clips)
      final target = controller.getSeekTargetFor(gapTime);
      expect(target, isNull);
    });

    test('getSeekTarget finds second segment (12:25)', () {
      final sec2 = now.add(const Duration(minutes: 25)); // 12:25
      final target = controller.getSeekTargetFor(sec2);
      expect(target, isNotNull);
      expect(target!.recording.id, '2');
      expect(target.offset, const Duration(minutes: 5));
    });

    test('isGap returns true for gaps', () {
      expect(controller.isGap(now.add(const Duration(minutes: 15))), isTrue);
    });

    test('isGap returns false for valid data', () {
      expect(controller.isGap(now.add(const Duration(minutes: 5))), isFalse);
    });
  });
}
