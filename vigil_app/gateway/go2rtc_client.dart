import 'dart:convert';
import 'package:http/http.dart' as http;

/// Go2RTC HTTP API Client
/// Manages dynamic stream registration per camera
class Go2RtcClient {
  static const String _baseUrl = 'http://127.0.0.1:1984';

  /// Generate stream ID from camera UUID
  String generateStreamId(String cameraId) {
    final shortId = cameraId.length >= 8 ? cameraId.substring(0, 8) : cameraId;
    return 'cam_$shortId';
  }

  /// Check if Go2RTC is reachable
  Future<bool> isOnline() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/streams'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get all registered streams from Go2RTC
  Future<Map<String, dynamic>> getAllStreams() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/streams'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('   ⚠️ Failed to get streams: $e');
    }
    return {};
  }

  /// Find an existing stream by IP address
  /// Returns the stream ID if found, null otherwise
  Future<String?> findStreamByIp(String rtspUrl) async {
    try {
      // Extract IP from RTSP URL
      final ipMatch = RegExp(r'@(\d+\.\d+\.\d+\.\d+)').firstMatch(rtspUrl);
      if (ipMatch == null) {
        // Try URL without auth
        final ipMatch2 =
            RegExp(r'rtsp://(\d+\.\d+\.\d+\.\d+)').firstMatch(rtspUrl);
        if (ipMatch2 == null) return null;
        return await _findStreamWithIp(ipMatch2.group(1)!);
      }
      return await _findStreamWithIp(ipMatch.group(1)!);
    } catch (e) {
      print('   ⚠️ Failed to find stream by IP: $e');
      return null;
    }
  }

  Future<String?> _findStreamWithIp(String ip) async {
    final streams = await getAllStreams();

    for (final entry in streams.entries) {
      final streamId = entry.key;
      final streamData = entry.value;

      // Check if this stream has a producer with matching IP
      if (streamData is Map && streamData.containsKey('producers')) {
        final producers = streamData['producers'] as List?;
        if (producers != null) {
          for (final producer in producers) {
            if (producer is Map) {
              final url = producer['url'] as String?;
              final remoteAddr = producer['remote_addr'] as String?;

              if ((url != null && url.contains(ip)) ||
                  (remoteAddr != null && remoteAddr.contains(ip))) {
                print('   🔍 Found existing stream: $streamId for IP $ip');
                return streamId;
              }
            }
          }
        }
      }

      // Also check static config
      if (streamData is List) {
        for (final url in streamData) {
          if (url is String && url.contains(ip)) {
            print('   🔍 Found existing stream: $streamId for IP $ip');
            return streamId;
          }
        }
      }
    }

    print('   ℹ️ No existing stream found for IP $ip');
    return null;
  }

  /// Get or create a stream for the given camera
  /// First checks for existing streams, then tries dynamic registration
  Future<String?> getOrCreateStream(String cameraId, String rtspUrl) async {
    final preferredId = generateStreamId(cameraId);

    // 1. Check if our preferred stream ID already exists
    if (await streamExists(preferredId)) {
      print('   ✅ Using existing stream: $preferredId');
      return preferredId;
    }

    // 2. Check if there's an existing stream for this camera's IP
    final existingStream = await findStreamByIp(rtspUrl);
    if (existingStream != null) {
      print('   ✅ Using existing stream by IP: $existingStream');
      return existingStream;
    }

    // 3. Try to register a new stream
    print('   🔧 Attempting dynamic registration...');
    final registered = await registerStream(preferredId, rtspUrl);
    if (registered) {
      return preferredId;
    }

    // 4. If registration failed, check if any stream with this IP appeared
    await Future.delayed(Duration(milliseconds: 500));
    final fallbackStream = await findStreamByIp(rtspUrl);
    if (fallbackStream != null) {
      print('   ✅ Using fallback stream: $fallbackStream');
      return fallbackStream;
    }

    print('   ❌ No stream available for this camera');
    return null;
  }

  /// Register a new stream with Go2RTC
  Future<bool> registerStream(String streamId, String rtspUrl) async {
    try {
      print('   🔗 Registering: $streamId');

      // Build URL manually to avoid encoding issues
      final encodedSrc = Uri.encodeQueryComponent(streamId);
      final encodedUrl = Uri.encodeQueryComponent(rtspUrl);
      final requestUrl =
          '$_baseUrl/api/streams?src=$encodedSrc&url=$encodedUrl';

      print('   📤 PUT $requestUrl');

      final response = await http.put(Uri.parse(requestUrl));

      print('   📥 Response: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await Future.delayed(Duration(milliseconds: 500));
        if (await streamExists(streamId)) {
          print('   ✅ Stream registered');
          return true;
        }
      }

      print(
          '   ⚠️ Registration returned ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      print('   ❌ Registration error: $e');
      return false;
    }
  }

  /// Check if a stream exists
  Future<bool> streamExists(String streamId) async {
    try {
      final streams = await getAllStreams();
      return streams.containsKey(streamId);
    } catch (e) {
      return false;
    }
  }

  /// Get stream URL for FFmpeg consumption
  String getStreamUrl(String streamId) {
    return '$_baseUrl/api/stream.mp4?src=$streamId';
  }
}
