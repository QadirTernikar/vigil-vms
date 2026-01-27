import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SnapshotService {
  // Uses Playback Server (8090) for Media storage
  static const String _gatewayUrl = 'http://127.0.0.1:8090/snapshot';

  Future<void> uploadSnapshot(
    String cameraId,
    String cameraName,
    Uint8List imageBytes,
  ) async {
    try {
      final encodedName = Uri.encodeQueryComponent(cameraName);
      final uri = Uri.parse(
        '$_gatewayUrl?camera_id=$cameraId&camera_name=$encodedName',
      );
      debugPrint('📸 Uploading snapshot to Gateway: $uri');

      final response = await http.post(
        uri,
        body: imageBytes,
        headers: {'Content-Type': 'image/jpeg'},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Gateway upload failed: ${response.statusCode} ${response.body}',
        );
      }

      debugPrint('✅ Snapshot upload success');
    } catch (e) {
      debugPrint('❌ Snapshot Error: $e');
      rethrow;
    }
  }

  // Helper to get URL for UI (e.g. Image.network)
  String getSnapshotUrl(String cameraId) {
    return '$_gatewayUrl?camera_id=$cameraId&t=${DateTime.now().millisecondsSinceEpoch}'; // Cache buster
  }
}
