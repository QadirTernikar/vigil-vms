import 'package:flutter/material.dart';

/// MSE Stream Player - Placeholder for WebView-based Go2RTC MSE stream
///
/// NOTE: The webview_windows package is not currently installed.
/// This is a fallback player that would use WebView to display Go2RTC's MSE stream
/// when WebRTC ICE fails (Windows/Docker environments).
///
/// To enable this feature, add to pubspec.yaml:
///   webview_windows: ^0.4.0
///
/// For Sprint 1, this is stubbed out as it's not part of the security/auth scope.
class MseStreamPlayer extends StatefulWidget {
  final String streamId;
  final String host;

  const MseStreamPlayer({
    super.key,
    required this.streamId,
    required this.host,
  });

  @override
  State<MseStreamPlayer> createState() => _MseStreamPlayerState();
}

class _MseStreamPlayerState extends State<MseStreamPlayer> {
  @override
  Widget build(BuildContext context) {
    // Placeholder UI until webview_windows is added
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web_asset, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              'MSE Player Unavailable',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'WebView support not installed',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
