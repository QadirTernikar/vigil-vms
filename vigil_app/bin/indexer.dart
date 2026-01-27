import 'dart:io';
import 'package:supabase/supabase.dart';
import '../lib/core/config/constants.dart';

// M6-2 Recording Indexer
// Scans local recording folders and populates Supabase metadata
// Does NOT upload media - only indexes file paths and timestamps

// --- Configuration ---
const String kRecordingsRoot = 'go2rtc\\recordings';
const int kSegmentDuration = 60; // Seconds

Future<void> main() async {
  print('═══════════════════════════════════════════════');
  print('🔎 Vigil M6-2 Recording Indexer (Auto-Discovery Mode)');
  print('═══════════════════════════════════════════════');
  print('📂 Root: $kRecordingsRoot');
  print('');

  // Initialize Supabase (Pure Dart Client)
  final supabase = SupabaseClient(
    AppConstants.supabaseUrl,
    AppConstants.supabaseAnonKey,
  );

  // Scan Loop
  while (true) {
    try {
      await _scanAllCameras(supabase);
    } catch (e, stackTrace) {
      print('❌ Error during scan: $e');
      print(stackTrace);
    }

    print('⏳ Waiting 10 seconds before next scan...\n');
    await Future.delayed(const Duration(seconds: 10));
  }
}

Future<void> _scanAllCameras(SupabaseClient supabase) async {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔄 Starting scan cycle: ${DateTime.now().toIso8601String()}');

  final rootDir = Directory(kRecordingsRoot);
  if (!await rootDir.exists()) {
    print('⚠️ Recordings root not found: $kRecordingsRoot');
    return;
  }

  // 1. Fetch Cameras to map Name -> ID
  // We need ID for Foreign Key (if enforcing)
  Map<String, String> nameToId = {};
  try {
    final response = await supabase.from('cameras').select('id, name');
    for (var row in response as List) {
      nameToId[row['name'] as String] = row['id'] as String;
    }
    print('📋 Loaded ${nameToId.length} cameras from DB');
  } catch (e) {
    print('⚠️ Failed to load cameras: $e');
  }

  // 2. Scan Directory
  final cameraFolders = rootDir
      .listSync()
      .where((e) => e is Directory)
      .cast<Directory>()
      .toList();

  print('📹 Discovered ${cameraFolders.length} camera folder(s)');

  for (final folder in cameraFolders) {
    // UPDATED ARCHITECTURE: Folder name IS the Camera ID (UUID)
    final cameraId = folder.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

    // Attempt to look up the name for logging, but ID is primary
    // We reverse the lookup: ID -> Name
    String cameraName = "Unknown";
    try {
      // We don't have an Id->Name map handy, but we can query it or just use "Unknown"
      // The previous code built nameToId, let's just proceed with ID.
    } catch (_) {}

    print('\n📹 Scanning folder: $cameraId (ID)');
    await _scanCamera(supabase, cameraId, cameraId);
  }

  print('\n✅ Scan cycle complete.');
}

Future<void> _scanCamera(
  SupabaseClient supabase,
  String cameraName,
  String? uuid,
) async {
  final cameraDir = Directory('$kRecordingsRoot\\$cameraName');

  if (!await cameraDir.exists()) {
    print('   ⚠️ Directory not found: ${cameraDir.path}');
    return;
  }

  // Find all date folders (YYYY-MM-DD)
  final dateFolders = cameraDir
      .listSync()
      .where((e) => e is Directory)
      .cast<Directory>()
      .toList();

  if (dateFolders.isEmpty) {
    print('   ℹ️  No date folders found');
    return;
  }

  print('   📂 Found ${dateFolders.length} date folder(s)');

  int newCount = 0;
  int existingCount = 0;

  for (final dateFolder in dateFolders) {
    final dateName =
        dateFolder.uri.pathSegments[dateFolder.uri.pathSegments.length - 2];

    // Get all MP4 files in this date folder
    final mp4Files =
        dateFolder.listSync().where((f) => f.path.endsWith('.mp4')).toList();

    if (mp4Files.isEmpty) continue;

    print('   📅 $dateName: ${mp4Files.length} segment(s)');

    for (var file in mp4Files) {
      final filename = file.uri.pathSegments.last;

      try {
        // Parse: "HH-MM-SS.mp4" format
        final timestamps = _parseM6Timestamp(dateName, filename);
        final start = timestamps[0];
        final end = timestamps[1];
        final absPath = file.absolute.path;

        // Check exist
        // We check by file_path since that's unique
        final existing = await supabase
            .from('recordings')
            .select('id')
            .eq('file_path', absPath)
            .maybeSingle();

        if (existing == null) {
          // Insert
          // If we have UUID, use it. If not, can we insert?
          // If 'camera_id' is NOT NULL constraint -> We fail if UUID unknown.
          // We'll update to support 'camera_name' column if present.
          final row = {
            'file_path': absPath,
            'start_time': start.toIso8601String(), // Local with offset
            'end_time': end.toIso8601String(),
            'duration_seconds': kSegmentDuration,
            'camera_name': cameraName, // NEW Requirement
          };
          if (uuid != null) row['camera_id'] = uuid;

          try {
            await supabase.from('recordings').insert(row);
            print('      ✨ NEW: $filename');
            newCount++;
          } catch (e) {
            print('      ⚠️ Insert Failed (Schema mismatch?): $e');
          }
        } else {
          existingCount++;
        }
      } catch (e) {
        print('      ⚠️ Error: $e');
      }
    }
  }

  if (newCount > 0) {
    print('   ✅ Indexed $newCount new segment(s)');
  }
  if (existingCount > 0) {
    print('   ℹ️  Skipped $existingCount existing segment(s)');
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

  // Use Local DateTime constructor (because ffmpeg writes Local Time)
  // .toIso8601String() will include offset (e.g. +05:30) which Supabase handles correctly.
  final start = DateTime(year, month, day, hour, minute, second);
  final end = start.add(const Duration(seconds: kSegmentDuration));

  return [start, end];
}
