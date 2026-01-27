/**
 * Vigil VMS - Recording Controller (Professional Architecture)
 * 
 * Event-Driven Recording Pipeline:
 * - Camera Registry: Manages N concurrent camera sessions
 * - Go2RTC Integration: Dynamic stream registration per camera_id
 * - Segment Watcher: File system monitoring for closed segments
 * - Resilient Indexing: Local-first + background syncing to Supabase
 * 
 * NO polling, NO batch scanning, NO manual YAML.
 * Each camera is independent. Recording never blocks playback.
 */

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'go2rtc_client.dart';
import 'segment_watcher.dart';
import 'index_queue.dart';
import 'live_indexer.dart';
import 'scheduler_service.dart';

// ============================================================================
// CAMERA REGISTRY - Core Control Plane
// ============================================================================

/// State of a recording session
enum RecordingState { starting, recording, stopping, stopped, error }

/// Represents an active camera recording session
class CameraSession {
  final String cameraId;
  final String cameraName;
  final String streamId;
  final String rtspUrl;
  final Process ffmpegProcess;
  final SegmentWatcher segmentWatcher;
  final String recordingDir;
  final DateTime startTime;
  RecordingState state;
  int segmentsIndexed = 0;

  CameraSession({
    required this.cameraId,
    required this.cameraName,
    required this.streamId,
    required this.rtspUrl,
    required this.ffmpegProcess,
    required this.segmentWatcher,
    required this.recordingDir,
    required this.startTime,
    this.state = RecordingState.recording,
  });
}

/// Camera Registry - Manages all active recording sessions
class CameraRegistry {
  final Map<String, CameraSession> _sessions = {};

  /// Add a new camera session
  void add(CameraSession session) {
    _sessions[session.cameraId] = session;
    print(
        '📋 Registry: Added ${session.cameraName} (${_sessions.length} active)');
  }

  /// Remove a camera session
  CameraSession? remove(String cameraId) {
    final session = _sessions.remove(cameraId);
    if (session != null) {
      print(
          '📋 Registry: Removed ${session.cameraName} (${_sessions.length} active)');
    }
    return session;
  }

  /// Get session by camera ID
  CameraSession? get(String cameraId) => _sessions[cameraId];

  /// Check if camera is recording
  bool isRecording(String cameraId) => _sessions.containsKey(cameraId);

  /// Get status summary
  Map<String, dynamic> getStatus() {
    return {
      'active_count': _sessions.length,
      'cameras': _sessions.values
          .map((s) => {
                'camera_id': s.cameraId,
                'camera_name': s.cameraName,
                'state': s.state.name,
                'segments_indexed': s.segmentsIndexed,
                'uptime_seconds':
                    DateTime.now().difference(s.startTime).inSeconds,
              })
          .toList(),
    };
  }
}

// ============================================================================
// GLOBALS
// ============================================================================

final CameraRegistry _registry = CameraRegistry();
final Go2RtcClient _go2rtc = Go2RtcClient();
final IndexQueue _queue = IndexQueue();
final ResilientIndexer _indexer =
    ResilientIndexer(queue: _queue, segmentDuration: 10);
late final SchedulerService _scheduler;

// ============================================================================
// MAIN
// ============================================================================

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('🔴 VIGIL VMS - PROFESSIONAL RECORDING CONTROLLER');
  print('═══════════════════════════════════════════════════════════════');
  print('   Mode: Event-Driven Pipeline');
  print('   Features:');
  print('     • Camera Registry (N-camera support)');
  print('     • Dynamic Go2RTC Registration');
  print('     • Resilient Local-First Indexing (Offline Safe)');
  print('     • Playback-While-Recording');
  print('     • Time-Based Scheduler');
  print('');

  // Initialize Resilient Indexer
  await _indexer.init();

  // Initialize Scheduler
  _scheduler = SchedulerService(
    onStartRecording: _startRecordingInternal,
    onStopRecording: _stopRecordingInternal,
  );
  await _scheduler.init();

  // Check Go2RTC connectivity
  final go2rtcOnline = await _go2rtc.isOnline();
  print('   Go2RTC: ${go2rtcOnline ? "✅ Online" : "❌ Offline"}');
  print('');

  final router = Router();

  // Recording endpoints
  router.post('/record/start', _handleStart);
  router.post('/record/stop', _handleStop);
  router.get('/record/status', _handleStatus);
  router.get('/record/registry', _handleRegistry);
  router.get('/record/queue', _handleQueueStatus);
  router.get('/record/queue/segments', _handleQueueSegments);

  // Scheduler endpoints
  router.post('/schedule/add', _handleScheduleAdd);
  router.get('/schedule/list', _handleScheduleList);
  router.delete('/schedule/remove', _handleScheduleRemove);

  // Health check
  router.get('/health', (Request request) {
    return Response.ok(
      '{"status":"ok","service":"recording_controller"}',
      headers: {'Content-Type': 'application/json'},
    );
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsHeaders())
      .addHandler(router);

  final server = await io.serve(handler, '127.0.0.1', 8091);
  print(
      '✅ Recording Controller running on http://${server.address.host}:${server.port}');
  print('═══════════════════════════════════════════════════════════════');
}

Middleware _corsHeaders() {
  return (Handler innerHandler) => (Request request) async {
        final response = await innerHandler(request);
        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          },
        );
      };
}

// ============================================================================
// HANDLERS
// ============================================================================

Future<Response> _handleStart(Request request) async {
  final params = request.url.queryParameters;
  final cameraId = params['camera_id'];
  final cameraName = params['camera_name'] ?? 'Unknown';
  final rtspUrl = params['rtsp_url'];

  // Validation
  if (cameraId == null || cameraId.isEmpty) {
    return _jsonError(400, 'Missing camera_id');
  }
  if (rtspUrl == null || rtspUrl.isEmpty) {
    return _jsonError(400, 'Missing rtsp_url');
  }
  if (_registry.isRecording(cameraId)) {
    return _jsonError(409, 'Camera already recording');
  }

  print('');
  print('▶ START RECORDING');
  print('  Camera: $cameraName');
  print('  ID: $cameraId');

  try {
    // 1. Get or find existing stream for this camera
    final streamId = await _go2rtc.getOrCreateStream(cameraId, rtspUrl);
    if (streamId == null) {
      return _jsonError(502,
          'No Go2RTC stream available for this camera. Check if camera is configured in go2rtc.yaml');
    }
    print('  Stream ID: $streamId');

    // 2. Create recording directory
    final now = DateTime.now();
    final dateFolder =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final recordingDir = 'go2rtc/recordings/$cameraId/$dateFolder';

    final dir = Directory(recordingDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    print('  📂 Recording to: $recordingDir');

    // 3. Start FFmpeg
    final streamUrl = _go2rtc.getStreamUrl(streamId);
    print('  🔗 Source: $streamUrl');

    final ffmpegArgs = [
      '-y',
      '-i', streamUrl,
      '-c', 'copy',
      '-f', 'segment',
      '-segment_time', '10', // 10 second segments for responsiveness
      '-segment_format', 'mp4',
      '-strftime', '1',
      '-reset_timestamps', '1',
      '$recordingDir/%H-%M-%S.mp4',
    ];

    print('  🚀 Starting FFmpeg...');
    final process = await Process.start('go2rtc/ffmpeg.exe', ffmpegArgs);

    // Monitor FFmpeg stderr for errors
    process.stderr.transform(utf8.decoder).listen((data) {
      if (data.toLowerCase().contains('error')) {
        print('  ⚠️ FFmpeg Error: ${data.trim()}');
      }
    });

    // 4. Create Segment Watcher with Resilient Indexer callback
    final watcher = SegmentWatcher(
      directoryPath: recordingDir,
      onSegmentClosed: (event) async {
        final session = _registry.get(cameraId);
        if (session == null) return;

        // Queue segment for indexing (Local-First Guarantee)
        // This will sync to Supabase in background
        await _indexer.queueSegment(
          cameraId: cameraId,
          cameraName: cameraName,
          filePath: event.filePath,
          fileName: event.fileName,
          startTime: event.startTime,
          fileSize: event.fileSize,
        );

        session.segmentsIndexed++;
      },
    );
    watcher.start();

    // 5. Create and register session
    final session = CameraSession(
      cameraId: cameraId,
      cameraName: cameraName,
      streamId: streamId,
      rtspUrl: rtspUrl,
      ffmpegProcess: process,
      segmentWatcher: watcher,
      recordingDir: recordingDir,
      startTime: now,
    );
    _registry.add(session);

    // Wait for FFmpeg to initialize
    await Future.delayed(Duration(seconds: 2));

    print('  ✅ Recording STARTED');
    print('');

    return _jsonResponse(200, {
      'status': 'started',
      'camera_id': cameraId,
      'stream_id': streamId,
      'recording_dir': recordingDir,
      'pid': process.pid,
    });
  } catch (e, stack) {
    print('  ❌ Failed: $e');
    print(stack);
    return _jsonError(500, e.toString());
  }
}

Future<Response> _handleStop(Request request) async {
  final cameraId = request.url.queryParameters['camera_id'];

  if (cameraId == null || cameraId.isEmpty) {
    return _jsonError(400, 'Missing camera_id');
  }

  final session = _registry.get(cameraId);
  if (session == null) {
    return _jsonError(404, 'Camera not recording');
  }

  print('');
  print('⏹ STOP RECORDING');
  print('  Camera: ${session.cameraName}');

  try {
    // 1. Stop segment watcher
    session.segmentWatcher.stop();

    // 2. Kill FFmpeg process
    session.ffmpegProcess.kill(ProcessSignal.sigterm);
    if (Platform.isWindows) {
      await Process.run(
          'taskkill', ['/F', '/PID', '${session.ffmpegProcess.pid}']);
    }

    // 3. Remove from registry
    _registry.remove(cameraId);

    final duration = DateTime.now().difference(session.startTime);

    print('  ✅ Recording STOPPED');
    print('  Duration: ${duration.inMinutes}m ${duration.inSeconds % 60}s');
    print('  Segments indexed: ${session.segmentsIndexed}');
    print('');

    return _jsonResponse(200, {
      'status': 'stopped',
      'camera_id': cameraId,
      'duration_seconds': duration.inSeconds,
      'segments_indexed': session.segmentsIndexed,
    });
  } catch (e) {
    print('  ❌ Stop failed: $e');
    _registry.remove(cameraId);
    return _jsonError(500, e.toString());
  }
}

Future<Response> _handleStatus(Request request) async {
  final cameraId = request.url.queryParameters['camera_id'];

  if (cameraId != null) {
    final session = _registry.get(cameraId);
    return _jsonResponse(200, {
      'camera_id': cameraId,
      'is_recording': session != null,
      'state': session?.state.name ?? 'stopped',
      'segments_indexed': session?.segmentsIndexed ?? 0,
    });
  }

  return _jsonResponse(200, _registry.getStatus());
}

Future<Response> _handleRegistry(Request request) async {
  return _jsonResponse(200, _registry.getStatus());
}

Future<Response> _handleQueueStatus(Request request) async {
  return _jsonResponse(200, _indexer.getStatus());
}

Future<Response> _handleQueueSegments(Request request) async {
  final cameraId = request.url.queryParameters['camera_id'];

  List<Map<String, dynamic>> segments;

  if (cameraId == null || cameraId.isEmpty) {
    segments = _indexer.getLocalSegmentsAll().map((s) => s.toJson()).toList();
  } else {
    segments =
        _indexer.getLocalSegments(cameraId).map((s) => s.toJson()).toList();
  }

  return _jsonResponse(200, {'segments': segments});
}

// ============================================================================
// SCHEDULER HANDLERS
// ============================================================================

Future<Response> _handleScheduleAdd(Request request) async {
  try {
    final bodyStr = await request.readAsString();
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;

    final schedule = Schedule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      cameraId: body['camera_id'],
      cameraName: body['camera_name'],
      rtspUrl: body['rtsp_url'],
      type: ScheduleType.values.byName(body['type'] ?? 'daily'),
      startTime: DateTime.parse(body['start_time']),
      endTime:
          body['end_time'] != null ? DateTime.parse(body['end_time']) : null,
      weekdays:
          body['weekdays'] != null ? List<int>.from(body['weekdays']) : null,
    );

    final id = _scheduler.addSchedule(schedule);
    return _jsonResponse(200, {'id': id, 'message': 'Schedule added'});
  } catch (e) {
    return _jsonError(400, 'Invalid schedule data: $e');
  }
}

Future<Response> _handleScheduleList(Request request) async {
  final schedules = _scheduler.listSchedules().map((s) => s.toJson()).toList();
  return _jsonResponse(200, {'schedules': schedules});
}

Future<Response> _handleScheduleRemove(Request request) async {
  final id = request.url.queryParameters['id'];
  if (id == null) return _jsonError(400, 'Missing schedule id');

  final removed = _scheduler.removeSchedule(id);
  if (removed) {
    return _jsonResponse(200, {'message': 'Schedule removed'});
  } else {
    return _jsonError(404, 'Schedule not found');
  }
}

// Internal methods for scheduler callbacks - FULL IMPLEMENTATION
Future<void> _startRecordingInternal(
    String cameraId, String cameraName, String rtspUrl) async {
  // Prevent duplicates
  if (_registry.isRecording(cameraId)) {
    print('⏰ Scheduler: $cameraName already recording, skipping');
    return;
  }

  print('');
  print('⏰ SCHEDULER START RECORDING');
  print('  Camera: $cameraName');
  print('  ID: $cameraId');

  try {
    // 1. Get or create stream
    final streamId = await _go2rtc.getOrCreateStream(cameraId, rtspUrl);
    if (streamId == null) {
      print('  ❌ No Go2RTC stream available');
      return;
    }
    print('  Stream ID: $streamId');

    // 2. Create recording directory
    final now = DateTime.now();
    final dateFolder =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final recordingDir = 'go2rtc/recordings/$cameraId/$dateFolder';

    final dir = Directory(recordingDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    print('  📂 Recording to: $recordingDir');

    // 3. Start FFmpeg
    final streamUrl = _go2rtc.getStreamUrl(streamId);
    print('  🔗 Source: $streamUrl');

    final ffmpegArgs = [
      '-y',
      '-i',
      streamUrl,
      '-c',
      'copy',
      '-f',
      'segment',
      '-segment_time',
      '10',
      '-segment_format',
      'mp4',
      '-strftime',
      '1',
      '-reset_timestamps',
      '1',
      '$recordingDir/%H-%M-%S.mp4',
    ];

    print('  🚀 Starting FFmpeg...');
    final process = await Process.start('go2rtc/ffmpeg.exe', ffmpegArgs);

    process.stderr.transform(utf8.decoder).listen((data) {
      if (data.toLowerCase().contains('error')) {
        print('  ⚠️ FFmpeg Error: ${data.trim()}');
      }
    });

    // 4. Create Segment Watcher
    final watcher = SegmentWatcher(
      directoryPath: recordingDir,
      onSegmentClosed: (event) async {
        final session = _registry.get(cameraId);
        if (session == null) return;

        await _indexer.queueSegment(
          cameraId: cameraId,
          cameraName: cameraName,
          filePath: event.filePath,
          fileName: event.fileName,
          startTime: event.startTime,
          fileSize: event.fileSize,
        );

        session.segmentsIndexed++;
      },
    );
    watcher.start();

    // 5. Register session
    final session = CameraSession(
      cameraId: cameraId,
      cameraName: cameraName,
      streamId: streamId,
      rtspUrl: rtspUrl,
      ffmpegProcess: process,
      segmentWatcher: watcher,
      recordingDir: recordingDir,
      startTime: now,
    );
    _registry.add(session);

    await Future.delayed(Duration(seconds: 2));

    print('  ✅ Scheduler recording STARTED');
    print('');
  } catch (e, stack) {
    print('  ❌ Scheduler start failed: $e');
    print(stack);
  }
}

Future<void> _stopRecordingInternal(String cameraId) async {
  // Prevent stopping non-existent recordings
  if (!_registry.isRecording(cameraId)) {
    print('⏰ Scheduler: $cameraId not recording, skipping stop');
    return;
  }

  final session = _registry.get(cameraId)!;

  print('');
  print('⏰ SCHEDULER STOP RECORDING');
  print('  Camera: ${session.cameraName}');

  try {
    // 1. Stop segment watcher
    session.segmentWatcher.stop();

    // 2. Kill FFmpeg process
    session.ffmpegProcess.kill(ProcessSignal.sigterm);
    if (Platform.isWindows) {
      await Process.run(
          'taskkill', ['/F', '/PID', '${session.ffmpegProcess.pid}']);
    }

    // 3. Remove from registry
    _registry.remove(cameraId);

    final duration = DateTime.now().difference(session.startTime);

    print('  ✅ Scheduler recording STOPPED');
    print('  Duration: ${duration.inMinutes}m ${duration.inSeconds % 60}s');
    print('  Segments indexed: ${session.segmentsIndexed}');
    print('');
  } catch (e) {
    print('  ❌ Scheduler stop failed: $e');
  }
}

// ============================================================================
// HELPERS
// ============================================================================

Response _jsonResponse(int code, Map<String, dynamic> body) {
  return Response(
    code,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );
}

Response _jsonError(int code, String message) {
  return _jsonResponse(code, {'error': message});
}
