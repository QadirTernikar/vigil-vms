import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RecordingService {
  // Use localhost for Windows. For real Android/iOS, this IP logic must be dynamic or config-based.
  // M6 assumes Windows Local dev.
  final String _baseUrl = 'http://127.0.0.1:8091/record';

  /// Starts recording for a camera.
  /// [rtspUrl] is required for dynamic stream registration if the stream doesn't exist.
  Future<void> startRecording(
      String cameraId, String cameraName, String rtspUrl) async {
    final encodedName = Uri.encodeQueryComponent(cameraName);
    final encodedUrl = Uri.encodeQueryComponent(rtspUrl);
    final uri = Uri.parse(
      '$_baseUrl/start?camera_id=$cameraId&camera_name=$encodedName&rtsp_url=$encodedUrl',
    );

    debugPrint('🔴 Requesting Recording START: $uri');

    try {
      final response = await http.post(uri);
      if (response.statusCode != 200) {
        throw HttpException('Start failed: ${response.body}');
      }
      debugPrint('✅ Recording STARTED for $cameraName');
    } catch (e) {
      debugPrint('❌ Recording Service Error: $e');
      rethrow;
    }
  }

  /// Stops recording for a camera.
  Future<void> stopRecording(String cameraId) async {
    final uri = Uri.parse('$_baseUrl/stop?camera_id=$cameraId');
    debugPrint('⏹ Requesting Recording STOP: $uri');

    try {
      final response = await http.post(uri);
      if (response.statusCode != 200) {
        throw HttpException('Stop failed: ${response.body}');
      }
      debugPrint('✅ Recording STOPPED for $cameraId');
    } catch (e) {
      debugPrint('❌ Recording Service Error: $e');
      rethrow;
    }
  }

  /// Checks if a camera is currently recording.
  Future<bool> isRecording(String cameraId) async {
    final uri = Uri.parse('$_baseUrl/status?camera_id=$cameraId');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['is_recording'] == true;
      }
      return false;
    } catch (e) {
      // If server is down, assume not recording (UI will show stopped)
      // Or we could throw error to show "Gateway Offline" UI?
      // M6-5 expects robustness, so safe default is False.
      return false;
    }
  }
}
