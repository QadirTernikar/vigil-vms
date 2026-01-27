/**
 * Vigil VMS - Gateway Playback Server
 * M6-3: Playback API
 * 
 * Professional VMS-grade HTTP server that streams local MP4 recordings.
 * 
 * SECURITY NOTE (M6-3):
 * This server does NOT implement authentication. Any client can request any recording.
 * This is intentional for M6-3 single-user testing phase.
 * Authentication will be added in M6-7 (Security Layer).
 * DO NOT deploy this to production without M6-7 security.
 * 
 * Architecture:
 * - Streams from local disk (recordings/ folder)
 * - NO Supabase media involvement
 * - HTTP Range request support (seeking)
 * - Strict path validation (directory traversal protection)
 * 
 * Usage:
 *   dart run gateway/playback_server.dart
 * 
 * Endpoint:
 *   GET http://127.0.0.1:8090/play?file_path=C:\path\to\recording.mp4
 */

import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

void main() async {
  print('═══════════════════════════════════════════════');
  print('🎥 Vigil Gateway Playback Server');
  print('═══════════════════════════════════════════════');
  print('');
  print('⚠️  SECURITY WARNING:');
  print('   No authentication in M6-3. Single-user testing only.');
  print('   DO NOT deploy to production without M6-7.');
  print('');

  final router = Router();

  // Playback endpoint
  router.get('/play', _handlePlayback);

  // Snapshot Endpoints (M6-5 Local Storage)
  router.post('/snapshot', _handleSnapshotUpload);
  router.get('/snapshot', _handleSnapshotGet);
  router.get('/snapshot/list', _handleSnapshotList);
  router.delete('/snapshot', _handleSnapshotDelete);

  // Health check
  router.get('/health', (Request request) {
    return Response.ok(
      '{"status":"ok"}',
      headers: {'Content-Type': 'application/json'},
    );
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsHeaders())
      .addHandler(router);

  final server = await io.serve(handler, '127.0.0.1', 8090);

  print('✅ Server running on http://${server.address.host}:${server.port}');
  print('');
  print(
    '📂 Recordings folder: ${Directory('go2rtc/recordings').absolute.path}',
  );
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('Ready to serve recordings.');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

/// CORS middleware for cross-origin requests
Middleware _corsHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      return response.change(
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Range, Content-Type',
        },
      );
    };
  };
}

/// Main playback request handler
Future<Response> _handlePlayback(Request request) async {
  try {
    // Extract file path from query parameter
    final filePath = request.url.queryParameters['file_path'];

    if (filePath == null || filePath.isEmpty) {
      return _jsonError(400, 'Missing file_path parameter');
    }

    print('📥 Playback request: $filePath');

    // Validate path security (CRITICAL - M6-3 Constraint #1)
    if (!_isPathSafe(filePath)) {
      print('🚫 Access denied: Path validation failed');
      return _jsonError(403, 'Access denied');
    }

    // Check file exists
    final file = File(filePath);
    if (!await file.exists()) {
      print('❌ File not found: $filePath');
      return _jsonError(404, 'File not found');
    }

    // Get file size
    final fileSize = await file.length();

    // Handle Range requests (M6-3 Constraint #2: NON-OPTIONAL)
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null) {
      return await _handleRangeRequest(file, fileSize, rangeHeader);
    }

    // Full file response
    print('✅ Streaming full file: ${fileSize} bytes');
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'video/mp4',
        'Content-Length': fileSize.toString(),
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      },
    );
  } catch (e, stackTrace) {
    print('💥 Server error: $e');
    print(stackTrace);
    return _jsonError(500, 'Read failure');
  }
}

/// Handle HTTP Range request for seeking (M6-3 Constraint #2)
Future<Response> _handleRangeRequest(
  File file,
  int fileSize,
  String rangeHeader,
) async {
  try {
    // Parse Range header: "bytes=start-end"
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);

    if (match == null) {
      print('🚫 Invalid range format: $rangeHeader');
      return _jsonError(416, 'Invalid range');
    }

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    final end = (endStr == null || endStr.isEmpty)
        ? fileSize - 1
        : int.parse(endStr);

    // Validate range bounds
    if (start < 0 || end >= fileSize || start > end) {
      print('🚫 Range out of bounds: $start-$end (fileSize: $fileSize)');
      return Response(
        416,
        body: '{"error":"Invalid range"}',
        headers: {
          'Content-Type': 'application/json',
          'Content-Range': 'bytes */$fileSize',
        },
      );
    }

    final contentLength = end - start + 1;

    print(
      '✅ Streaming range: bytes $start-$end/$fileSize ($contentLength bytes)',
    );

    // Stream the requested byte range
    final stream = file.openRead(start, end + 1);

    return Response(
      206, // Partial Content
      body: stream,
      headers: {
        'Content-Type': 'video/mp4',
        'Content-Length': contentLength.toString(),
        'Content-Range': 'bytes $start-$end/$fileSize',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      },
    );
  } catch (e) {
    print('💥 Range request error: $e');
    return _jsonError(416, 'Invalid range');
  }
}

/// Production-grade path security validation
/// M6-3 Constraint #1: CRITICAL
bool _isPathSafe(String requestedPath) {
  try {
    // Resolve to canonical absolute paths (follows symlinks)
    final file = File(requestedPath);

    // Check file exists before resolving symlinks
    if (!file.existsSync()) {
      return false;
    }

    final canonical = file.resolveSymbolicLinksSync();
    final recordingsRoot = Directory('go2rtc/recordings').absolute.path;
    final canonicalRoot = Directory(recordingsRoot).resolveSymbolicLinksSync();

    // Must start with recordings root (prevents directory traversal)
    if (!canonical.startsWith(canonicalRoot)) {
      print('🚫 Path outside recordings: $canonical');
      return false;
    }

    // Reject URL-encoded traversal attempts (%2e%2e = ..)
    if (requestedPath.contains('%2e%2e') || requestedPath.contains('%2E%2E')) {
      print('🚫 URL-encoded traversal attempt: $requestedPath');
      return false;
    }

    // Reject any .. sequences (including mixed slashes)
    if (requestedPath.contains('..')) {
      print('🚫 Directory traversal attempt: $requestedPath');
      return false;
    }

    return true;
  } catch (e) {
    // Symlink resolution failed or path doesn't exist
    print('🚫 Path validation error: $e');
    return false;
  }
}

Response _jsonError(int statusCode, String message) {
  return Response(
    statusCode,
    body: '{"error":"$message"}',
    headers: {'Content-Type': 'application/json'},
  );
}

Response _jsonResponse(int statusCode, Map<String, dynamic> body) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );
}

// --- Snapshot Handlers ---

Future<Response> _handleSnapshotUpload(Request request) async {
  try {
    final cameraId = request.url.queryParameters['camera_id'];
    // Fallback: Use ID if Name is missing (though Client should send it now)
    final cameraName = request.url.queryParameters['camera_name'] ?? cameraId;

    if (cameraId == null || cameraId.isEmpty)
      return _jsonError(400, 'Missing camera_id');

    // Forensic Naming: snapshots/CameraName/YYYY-MM-DD/HH-MM-SS-mmm.jpg
    final now = DateTime.now().toUtc();
    final dateFolder =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeName =
        "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}-${now.millisecond.toString().padLeft(3, '0')}.jpg";

    // Sanitize CameraName for path safety (basic)
    final safeName = cameraName!.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    final snapshotDir = Directory('go2rtc/snapshots/$safeName/$dateFolder');
    if (!await snapshotDir.exists()) await snapshotDir.create(recursive: true);

    final file = File('${snapshotDir.path}/$timeName');
    final bytes = await request.read().expand((b) => b).toList();

    await file.writeAsBytes(bytes);
    print('📸 Forensic Snapshot saved: ${file.path}');

    return Response.ok(
      '{"status":"saved", "path": "${file.path}"}',
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('💥 Snapshot upload failed: $e');
    return _jsonError(500, 'Upload failed');
  }
}

Future<Response> _handleSnapshotList(Request request) async {
  try {
    final rootDir = Directory('go2rtc/snapshots');
    if (!await rootDir.exists()) return _jsonResponse(200, {"cameras": []});

    final Map<String, List<Map<String, dynamic>>> gallery = {};

    // Structure: snapshots/CameraName/YYYY-MM-DD/Time.jpg
    final camDirs = rootDir.listSync().whereType<Directory>();

    for (var camDir in camDirs) {
      final camName = camDir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      gallery[camName] = [];

      final dateDirs = camDir.listSync().whereType<Directory>();
      for (var dateDir in dateDirs) {
        final files = dateDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.jpg'),
        );
        for (var f in files) {
          // Rel Path: CameraName/Date/Time.jpg
          // We'll send a relative path key for retrieval
          final relPath = f.path.replaceAll(r'\', '/').split('snapshots/').last;
          gallery[camName]!.add({
            "path": relPath,
            "time": f.lastModifiedSync().toIso8601String(),
            "size": f.lengthSync(),
          });
        }
      }
      // Sort desc
      gallery[camName]!.sort((a, b) => b['time'].compareTo(a['time']));
    }

    return _jsonResponse(200, {"cameras": gallery});
  } catch (e) {
    return _jsonError(500, 'List failed: $e');
  }
}

Future<Response> _handleSnapshotGet(Request request) async {
  try {
    // Mode 1: Legacy/Latest (by ID) - NOT SUPPORTED in V2 Folder Structure cleanly without search.
    // Mode 2: By Path (Gallery) - query param 'path' relative to snapshots/

    final pathParam = request.url.queryParameters['path'];

    if (pathParam != null) {
      // Security Check: No .. traversal
      if (pathParam.contains('..')) return _jsonError(403, 'Invalid path');

      final file = File('go2rtc/snapshots/$pathParam');
      if (!await file.exists()) return _jsonError(404, 'Not found');

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'max-age=3600', // Cache allowed for specific files
        },
      );
    }

    return _jsonError(400, 'Missing path param');
  } catch (e) {
    print('💥 Snapshot fetch failed: $e');
    return _jsonError(500, 'Fetch failed');
  }
}

Future<Response> _handleSnapshotDelete(Request request) async {
  try {
    final pathParam = request.url.queryParameters['path'];
    if (pathParam == null) return _jsonError(400, 'Missing path param');

    if (pathParam.contains('..')) return _jsonError(403, 'Invalid path');

    final file = File('go2rtc/snapshots/$pathParam');
    if (await file.exists()) {
      await file.delete();
      print('🗑️ Deleted snapshot: $pathParam');
      return _jsonResponse(200, {"status": "deleted"});
    }
    return _jsonError(404, 'File not found');
  } catch (e) {
    return _jsonError(500, 'Delete failed: $e');
  }
}
