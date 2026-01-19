import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// MSE Stream Player - Uses WebView to display Go2RTC's MSE stream
/// This is a reliable fallback when WebRTC ICE fails (Windows/Docker).
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
  final _controller = WebviewController();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // Generate the Go2RTC embedded player URL
      // Go2RTC serves an HTML player at: http://host:1984/stream.html?src=streamId
      final playerUrl =
          'http://${widget.host}:1984/stream.html?src=${widget.streamId}&mode=mse';

      debugPrint('Loading MSE Player: $playerUrl');

      await _controller.loadUrl(playerUrl);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('MSE WebView Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                'WebView Error',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    return Webview(_controller);
  }
}
