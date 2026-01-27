/**
 * M6-2 Indexer Test - Standalone Version
 * 
 * This script tests the indexer logic without requiring the full Flutter app.
 * It simulates the indexer behavior and outputs what WOULD be inserted into Supabase.
 * 
 * Usage: dart run go2rtc/test_indexer.dart
 */

import 'dart:io';

void main() {
  print('═══════════════════════════════════════════════');
  print('🧪 M6-2 Recording Indexer - Test Mode');
  print('═══════════════════════════════════════════════\n');

  const kRecordingsRoot = 'go2rtc\\recordings';
  const kCameraIds = ['bunny', 'cam_445791032', 'cam_892175943'];
  const int kSegmentDuration = 60;

  int totalFound = 0;
  int totalWouldIndex = 0;

  for (final cameraId in kCameraIds) {
    print('📹 Scanning camera: $cameraId');

    final cameraDir = Directory('$kRecordingsRoot\\$cameraId');

    if (!cameraDir.existsSync()) {
      print('   ⚠️  Directory not found: ${cameraDir.path}\n');
      continue;
    }

    // Find all date folders (YYYY-MM-DD)
    final dateFolders = cameraDir
        .listSync()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();

    if (dateFolders.isEmpty) {
      print('   ℹ️   No date folders found\n');
      continue;
    }

    print('   📂 Found ${dateFolders.length} date folder(s)');

    for (final dateFolder in dateFolders) {
      final dateName =
          dateFolder.uri.pathSegments[dateFolder.uri.pathSegments.length - 2];

      // Get all MP4 files in this date folder
      final mp4Files = dateFolder
          .listSync()
          .where((f) => f.path.endsWith('.mp4'))
          .toList();

      if (mp4Files.isEmpty) continue;

      print('   📅 $dateName: ${mp4Files.length} segment(s)');
      totalFound += mp4Files.length;

      for (var file in mp4Files) {
        final filename = file.uri.pathSegments.last;

        try {
          // Parse: "HH-MM-SS.mp4" format
          final timestamps = _parseM6Timestamp(dateName, filename);
          final startTime = timestamps[0];
          final endTime = timestamps[1];
          final absolutePath = file.absolute.path;

          // Simulate database insert
          print('      ✅ WOULD INDEX: $filename');
          print('         📍 Path: $absolutePath');
          print('         ⏰ Start: ${startTime.toIso8601String()}');
          print('         ⏰ End:   ${endTime.toIso8601String()}');
          print('         ⏱️  Duration: $kSegmentDuration seconds\n');

          totalWouldIndex++;
        } catch (e) {
          print('      ❌ Parse error for $filename: $e\n');
        }
      }
    }
  }

  print('═══════════════════════════════════════════════');
  print('📊 Summary');
  print('═══════════════════════════════════════════════');
  print('Total MP4 files found: $totalFound');
  print('Would insert into DB:  $totalWouldIndex');
  print('\n✅ Test complete!\n');

  if (totalWouldIndex > 0) {
    print('📝 Next Steps:');
    print('   1. Fix Flutter SDK cache issue (flutter clean + pub get)');
    print('   2. Run actual indexer: dart run bin/indexer.dart');
    print('   3. Verify Supabase recordings table');
  } else {
    print('⚠️  No recordings found to index.');
    print('   Make sure you have recordings from M6-1 testing.');
  }
}

/// Parse M6-compliant format: YYYY-MM-DD/HH-MM-SS.mp4
List<DateTime> _parseM6Timestamp(String dateStr, String timeFilename) {
  // Date: "2026-01-21"
  final dateParts = dateStr.split('-');
  final year = int.parse(dateParts[0]);
  final month = int.parse(dateParts[1]);
  final day = int.parse(dateParts[2]);

  // Time: "13-10-30.mp4"
  final timeStr = timeFilename.replaceAll('.mp4', '');
  final timeParts = timeStr.split('-');
  final hour = int.parse(timeParts[0]);
  final minute = int.parse(timeParts[1]);
  final second = int.parse(timeParts[2]);

  final start = DateTime.utc(year, month, day, hour, minute, second);
  final end = start.add(const Duration(seconds: 60));

  return [start, end];
}
