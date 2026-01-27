import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  // Use stdout directly to avoid buffering issues
  stdout.writeln('🧪 TESTING Queue Segments API');

  try {
    // 1. Check Root Endpoint (All cameras)
    final url = Uri.parse('http://127.0.0.1:8091/record/queue/segments');
    stdout.writeln('GET $url');
    final response = await http.get(url);

    stdout.writeln('Status: ${response.statusCode}');
    stdout.writeln('Body: ${response.body}');

    if (response.statusCode != 200) {
      stdout.writeln('❌ Failed');
      return;
    }

    final data = jsonDecode(response.body);
    if (data is Map && data.containsKey('segments')) {
      final list = data['segments'] as List;
      stdout.writeln(
          '✅ Success! Found ${list.length} segments in queue structure.');
      // Write to file as backup
      File('test_api_result.txt')
          .writeAsStringSync('SUCCESS: ${list.length} segments');
    } else {
      stdout.writeln('❌ Invalid response format (missing "segments" key)');
    }
  } catch (e) {
    stdout.writeln('❌ Error: $e');
    File('test_api_result.txt').writeAsStringSync('ERROR: $e');
  }
}
