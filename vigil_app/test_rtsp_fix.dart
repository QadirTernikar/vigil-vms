import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // The User's exact problematic URL
  final rawUrl =
      'rtsp://admin:Vigil@123@192.168.1.13:554/stander/livestream/0/0';

  print('🧪 TESTING RTSP FIX');
  print('Input: $rawUrl');

  // 1. Run Sanitization Logic (Copied from go2rtc_client.dart)
  final sanitized = _sanitizeRtspUrl(rawUrl);
  print('Sanitized: $sanitized');

  if (sanitized == rawUrl) {
    print('❌ SANITIZATION FAILED (URL unchanged)');
  } else if (!sanitized.contains('%40')) {
    print('❌ SANITIZATION FAILED (No encoded @ found)');
  } else {
    print('✅ Sanitization Logic looks correct (contains %40)');
  }

  // 2. Try to Register with Go2RTC
  print('\n📡 Attempting Registration with Local Go2RTC...');
  try {
    final streamId = 'test_fix_debug';
    final baseUrl = 'http://127.0.0.1:1984';

    // Construct API call exactly as the client does
    final uri = Uri.parse(
        '$baseUrl/api/streams?src=${Uri.encodeComponent(streamId)}&url=${Uri.encodeComponent(sanitized)}');

    print('Request: $uri');

    final response = await http.put(uri);

    print('Response Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      print('🎉 SUCCESS! Go2RTC accepted the stream.');
    } else {
      print('💥 FAILURE! Go2RTC rejected it.');
    }
  } catch (e) {
    print('⚠️ Connection Error (Is Go2RTC running?): $e');
  }
}

// Logic copy-pasted from Go2RtcClient for verification
String _sanitizeRtspUrl(String rawUrl) {
  if (!rawUrl.toLowerCase().startsWith('rtsp://')) {
    return rawUrl;
  }

  try {
    final scheme = 'rtsp://';
    String body = rawUrl.substring(scheme.length);

    int lastAt = body.lastIndexOf('@');
    if (lastAt == -1) return rawUrl;

    String userInfo = body.substring(0, lastAt);
    String hostPath = body.substring(lastAt + 1);

    int colonIdx = userInfo.indexOf(':');
    if (colonIdx == -1) {
      String encodedUser = Uri.encodeComponent(userInfo);
      return '$scheme$encodedUser@$hostPath';
    }

    String user = userInfo.substring(0, colonIdx);
    String pass = userInfo.substring(colonIdx + 1);

    String encodedUser = Uri.encodeComponent(user);
    String encodedPass = Uri.encodeComponent(pass);

    return '$scheme$encodedUser:$encodedPass@$hostPath';
  } catch (e) {
    return rawUrl;
  }
}
