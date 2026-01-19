import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:vigil_app/features/dashboard/data/webrtc_service.dart';

enum StreamState { idle, loading, playing, reconnecting, error, offline }

class StreamPlayer extends ConsumerStatefulWidget {
  final String streamName;
  final String host; // e.g. 192.168.x.x

  const StreamPlayer({super.key, required this.streamName, required this.host});

  @override
  ConsumerState<StreamPlayer> createState() => _StreamPlayerState();
}

class _StreamPlayerState extends ConsumerState<StreamPlayer> {
  final _renderer = RTCVideoRenderer();
  late final WebRTCService _service;

  // State Machine
  StreamState _state = StreamState.idle;
  String? _errorMessage;
  int _retryCount = 0;
  static const int _maxRetries = 5;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _service = WebRTCService();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    _connect();
  }

  void _setState(StreamState newState, [String? error]) {
    if (!mounted) return;
    setState(() {
      _state = newState;
      if (error != null) _errorMessage = error;
    });
    // debugPrint("Stream [${widget.streamName}] State: $newState ${error ?? ''}");
  }

  Future<void> _connect() async {
    // Prevent double connect if already playing or loading
    if (_state == StreamState.playing || _state == StreamState.loading) return;

    _setState(_retryCount > 0 ? StreamState.reconnecting : StreamState.loading);

    try {
      // 1. Setup ICE state change callbacks with detailed logging
      _service.onIceStateChange = (state) {
        debugPrint('🔵 ICE State: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _handleConnectionFailure('ICE Disconnected/Failed');
        } else if (state ==
            RTCIceConnectionState.RTCIceConnectionStateConnected) {
          debugPrint('✅ ICE Connected! Video should be playing.');
        } else if (state ==
            RTCIceConnectionState.RTCIceConnectionStateChecking) {
          debugPrint('⏳ ICE Checking... (waiting for connectivity)');
        }
      };

      _service.onIceGatheringStateChange = (state) {
        debugPrint('🟡 ICE Gathering: $state');
      };

      _service.onIceCandidate = (candidate) {
        debugPrint('🔶 Local ICE Candidate generated');
      };

      // 2. Connectivity Check (Fast Fail)
      try {
        await http
            .get(Uri.parse('http://${widget.host}:1984/'))
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        throw Exception('Gateway Unreachable');
      }

      // 3. Connect WebRTC with onTrack callback
      await _service.connect(
        widget.streamName,
        widget.host,
        onTrackCallback: (stream) {
          debugPrint('🎥 OnTrack callback fired in StreamPlayer!');
          if (mounted) {
            _renderer.srcObject = stream;
            _setState(StreamState.playing);
            _retryCount = 0; // Reset retries on success
          }
        },
      );

      // 4. Watchdog for "Stuck Loading"
      // If we are still loading/reconnecting after 15s, force fail
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted &&
            (_state == StreamState.loading ||
                _state == StreamState.reconnecting)) {
          _handleConnectionFailure('Timeout: Video not received');
        }
      });
    } catch (e) {
      _handleConnectionFailure(e.toString());
    }
  }

  void _handleConnectionFailure(String error) {
    debugPrint('Stream Error [${widget.streamName}]: $error');

    // Cleanup previous connection attempt
    _service.disconnect();

    if (_retryCount < _maxRetries) {
      _retryCount++;
      int delaySeconds =
          2 * _retryCount; // Exponential-ish backoff: 2, 4, 6, 8, 10

      _setState(
        StreamState.reconnecting,
        'Retry $_retryCount/$_maxRetries in ${delaySeconds}s...',
      );

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delaySeconds), _connect);
    } else {
      _setState(StreamState.error, 'Stream Failed: $error');
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _renderer.dispose();
    _service.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Layer (Always present if we have a stream, to avoid black flash)
          RTCVideoView(
            _renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),

          // 2. Overlay Layer based on State
          if (_state == StreamState.loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            ),

          if (_state == StreamState.reconnecting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage ?? 'Reconnecting...',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          if (_state == StreamState.error)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.red, size: 32),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        _getFriendlyErrorMessage(_errorMessage),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_errorMessage?.contains('Timeout') == true)
                      const Text(
                        'Check Camera Power & Network',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () {
                        _retryCount = 0;
                        _connect();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Retry Now',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getFriendlyErrorMessage(String? error) {
    if (error == null) return 'Stream Error';
    if (error.contains('Gateway')) return 'Gateway Offline (Check PC)';
    if (error.contains('Timeout')) return 'Connection Timed Out';
    if (error.contains('ICE')) return 'Network Blocked (ICE)';
    if (error.contains('401')) return 'Authentication Failed';
    return 'Connection Failed';
  }

  /// Public method to capture snapshot from the current video frame
  Future<Uint8List?> captureSnapshot() async {
    try {
      if (_state != StreamState.playing) {
        debugPrint('❌ Cannot capture snapshot: Stream not playing');
        return null;
      }

      // Get the MediaStream from the renderer
      final stream = _renderer.srcObject;
      if (stream == null) {
        debugPrint('❌ No media stream available');
        return null;
      }

      // Get the video track
      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isEmpty) {
        debugPrint('❌ No video tracks in stream');
        return null;
      }

      debugPrint('📸 Capturing snapshot from video track...');

      // Capture frame from the video track
      final byteBuffer = await videoTracks[0].captureFrame();
      final bytes = byteBuffer.asUint8List();

      debugPrint('✅ Snapshot captured: ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      debugPrint('❌ Snapshot capture error: $e');
      return null;
    }
  }
}
