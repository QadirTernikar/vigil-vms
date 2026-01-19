import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SnapshotService {
  final _client = Supabase.instance.client;
  static const String _bucketName = 'snapshots';

  // 1. Capture Snapshot from Go2RTC
  Future<Uint8List?> captureFrame(
    String streamUrl, {
    String host = '127.0.0.1',
  }) async {
    try {
      // Generate the same streamId used by WebRTCService
      final streamId = 'cam_${streamUrl.hashCode.abs()}';

      // Go2RTC API: http://localhost:1984/api/frame.jpeg?src=streamId
      final url = 'http://$host:1984/api/frame.jpeg?src=$streamId';

      debugPrint('📸 Capturing snapshot from: $url');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        debugPrint('✅ Snapshot captured successfully');
        return response.bodyBytes;
      } else {
        debugPrint('❌ Snapshot failed: ${response.statusCode}');
        throw Exception('Failed to capture frame: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Snapshot Error: $e');
      throw Exception('Failed to capture frame');
    }
  }

  // 2. Upload to Supabase Storage and Return Public URL
  Future<String?> uploadSnapshot(String cameraId, Uint8List imageBytes) async {
    try {
      debugPrint('📤 Encoding ${imageBytes.length} bytes to JPEG...');

      // Use timestamp for unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$cameraId/$timestamp.jpg';

      debugPrint('📤 Uploading to Supabase: $path');

      // Upload raw bytes (already in frame format from VideoTrack)
      await _client.storage
          .from(_bucketName)
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(
              upsert: false, // Don't overwrite, create new
              contentType: 'image/jpeg',
            ),
          );

      final publicUrl = _client.storage.from(_bucketName).getPublicUrl(path);

      debugPrint('✅ Upload complete: $publicUrl');

      // Update Camera Record with latest snapshot URL
      await _client
          .from('cameras')
          .update({'snapshot_url': publicUrl})
          .eq('id', cameraId);

      return publicUrl;
    } catch (e) {
      debugPrint('❌ Upload Error: $e');
      return null;
    }
  }

  // Helper: Create bucket if not exists (Usually done via Supabase Dashboard, but useful helper)
  // Note: Only works if RLS policies allow bucket creation (Unlikely for Anon).
}
