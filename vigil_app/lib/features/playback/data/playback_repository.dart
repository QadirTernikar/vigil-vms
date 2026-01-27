/**
 * Playback Repository
 * M6-3: Playback API
 * 
 * VMS Architecture:
 * - Queries Supabase for recording metadata
 * - Builds playback URLs pointing to Gateway
 * - NO media from Supabase (metadata only)
 * 
 * SECURITY NOTE (M6-3):
 * No authentication validation yet. Added in M6-7.
 */

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/recording.dart';

class PlaybackRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Gateway playback server endpoint
  static const String kGatewayHost = '127.0.0.1';
  static const int kGatewayPort = 8090;

  /// Get list of cameras that have recordings (by Name)
  /// M6-5 Requirement: "SELECT DISTINCT camera_name FROM recordings"
  /// Also merges names found in local offline queue.
  Future<List<String>> getAvailablePlaybackCameras() async {
    try {
      final Set<String> uniqueNames = {};

      // 1. Fetch from Supabase
      try {
        final response =
            await _supabase.from('recordings').select('camera_name');

        for (var row in (response as List)) {
          final name = row['camera_name'] as String?;
          if (name != null && name.isNotEmpty) uniqueNames.add(name);
        }
      } catch (e) {
        print('   ⚠️ Supabase camera fetch failed: $e');
      }

      // 2. Fetch from Gateway Queue (Offline/Recent)
      try {
        final url =
            Uri.parse('http://$kGatewayHost:8091/record/queue/segments');
        final localRes =
            await http.get(url).timeout(const Duration(seconds: 1));
        if (localRes.statusCode == 200) {
          final data = jsonDecode(localRes.body);
          if (data is Map && data.containsKey('segments')) {
            for (var s in (data['segments'] as List)) {
              final name = s['camera_name'] as String?;
              if (name != null) uniqueNames.add(name);
            }
          }
        }
      } catch (e) {
        print('   ⚠️ Local queue camera fetch failed: $e');
      }

      // 3. Filter out UUID-like names (legacy data cleanup)
      final uuidRegex = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final filtered =
          uniqueNames.where((name) => !uuidRegex.hasMatch(name)).toList();

      filtered.sort();
      return filtered;
    } catch (e) {
      print('❌ Failed to fetch available playback cameras: $e');
      return [];
    }
  }

  /// Get all recordings for a camera on a specific date
  ///
  /// Merges data from:
  /// 1. Supabase (Cloud - Historical)
  /// 2. Gateway API (Local Queue - Recent/Offline)
  Future<List<Recording>> getRecordingsByDate({
    required String cameraName,
    required DateTime date,
  }) async {
    try {
      // 1. Fetch from Supabase (Cloud)
      final localStart = DateTime(date.year, date.month, date.day);
      final localEnd = localStart.add(const Duration(days: 1));
      final startStr = localStart.toIso8601String();
      final endStr = localEnd.toIso8601String();

      // Parallel fetch: Cloud + Local
      final futures = await Future.wait([
        _fetchFromSupabase(cameraName, startStr, endStr),
        _fetchFromLocalQueue(cameraName, date),
      ]);

      final cloudRecordings = futures[0];
      final localRecordings = futures[1];

      // 2. Merge and Deduplicate
      // Local takes precedence if duplication occurs (it's the source of truth for file existence)
      final Map<String, Recording> mergedMap = {};

      for (var r in cloudRecordings) {
        mergedMap[r.filePath] = r;
      }

      // Overwrite/Add local segments
      for (var r in localRecordings) {
        mergedMap[r.filePath] = r;
      }

      final mergedList = mergedMap.values.toList();
      mergedList.sort((a, b) => a.startTime.compareTo(b.startTime));

      print(
          '✅ Merged Recording List: ${cloudRecordings.length} Cloud + ${localRecordings.length} Local = ${mergedList.length} Total');

      return mergedList;
    } catch (e, stackTrace) {
      print('❌ Failed to query recordings: $e');
      print(stackTrace);
      return []; // Return empty list instead of crashing UI
    }
  }

  Future<List<Recording>> _fetchFromSupabase(
      String cameraName, String startStr, String endStr) async {
    try {
      final response = await _supabase
          .from('recordings')
          .select()
          .eq('camera_name', cameraName)
          .gte('start_time', startStr)
          .lt('start_time', endStr)
          .order('start_time', ascending: true);

      return (response as List)
          .map((json) => Recording.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('   ⚠️ Supabase query failed: $e');
      return [];
    }
  }

  Future<List<Recording>> _fetchFromLocalQueue(
      String cameraName, DateTime date) async {
    try {
      final url = Uri.parse('http://$kGatewayHost:8091/record/queue/segments');
      final response = await http.get(url).timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      if (data is! Map || !data.containsKey('segments')) return [];

      final list = data['segments'] as List;

      return list
          .map((json) => _mapQueueToRecording(json))
          .where(
              (r) => r.cameraName == cameraName && isSameDay(r.startTime, date))
          .toList();
    } catch (e) {
      print('   ⚠️ Local queue fetch failed: $e');
      return []; // Fail silently, show what we have
    }
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Recording _mapQueueToRecording(Map<String, dynamic> json) {
    // Map pending_segment.json structure to Recording model
    return Recording(
      id: 'local_${json['file_name']}', // Temporary ID
      cameraId: json['camera_id'],
      cameraName: json['camera_name'],
      filePath: json['file_path'],
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
    );
  }

  /// Build playback URL for a recording
  ///
  /// Points to Gateway HTTP server (NOT Supabase).
  /// Gateway streams from local disk.
  ///
  /// Format: http://127.0.0.1:8090/play?file_path=...
  String getPlaybackUrl(Recording recording) {
    // URL-encode file path to handle Windows paths with backslashes
    final encodedPath = Uri.encodeQueryComponent(recording.filePath);

    final url =
        'http://$kGatewayHost:$kGatewayPort/play?file_path=$encodedPath';

    print('🎥 Playback URL: $url');

    return url;
  }

  /// Check if Gateway playback server is reachable
  Future<bool> isGatewayOnline() async {
    try {
      final response = await http.get(
        Uri.parse('http://$kGatewayHost:$kGatewayPort/health'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ Gateway offline: $e');
      return false;
    }
  }
}
