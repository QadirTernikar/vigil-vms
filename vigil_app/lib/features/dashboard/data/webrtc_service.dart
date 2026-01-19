import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;

  // Callbacks
  void Function(RTCIceConnectionState)? onIceStateChange;
  void Function(RTCIceGatheringState)? onIceGatheringStateChange;
  void Function(RTCIceCandidate)? onIceCandidate;

  Future<MediaStream?> connect(
    String streamName,
    String host, {
    Function(MediaStream)? onTrackCallback,
  }) async {
    // 1. Create Peer Connection
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(config);

    // Monitor Connection States with Comprehensive Logging
    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('🔵 ICE Connection State: $state');
      onIceStateChange?.call(state);
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('🟢 Peer Connection State: $state');
    };

    _peerConnection!.onIceGatheringState = (state) {
      debugPrint('🟡 ICE Gathering State: $state');
      onIceGatheringStateChange?.call(state);
    };

    _peerConnection!.onIceCandidate = (candidate) {
      debugPrint('🔶 ICE Candidate: ${candidate.candidate}');
      debugPrint(
        '   Type: ${candidate.candidate?.split(' ').elementAtOrNull(7)}',
      );
      onIceCandidate?.call(candidate);
    };

    // CRITICAL: Set onTrack handler immediately after PeerConnection creation
    _peerConnection!.onTrack = (event) {
      debugPrint('🎥 OnTrack Event Received!');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        debugPrint('✅ Media Stream Available: ${_remoteStream!.id}');
        onTrackCallback?.call(_remoteStream!);
      } else {
        debugPrint('⚠️ OnTrack event but no streams');
      }
    };

    // 2. Add Transceiver (recvonly)
    await _peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await _peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    // 3. Create Offer
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // 4. Send Offer to Go2RTC API
    // Go2RTC endpoint: http://<host>:1984/api/webrtc?src=<stream>
    // It expects/returns SDP via POST

    // Adjust host for Android Emulator if needed
    final encodedStream = Uri.encodeComponent(streamName);

    // Generate a unique stream name for Go2RTC
    final streamId = 'cam_${streamName.hashCode.abs()}';

    debugPrint('--- WEBRTC CONNECT ---');
    debugPrint('Stream Name (Raw): $streamName');
    debugPrint('Stream ID: $streamId');

    // Step 1: Register the stream dynamically with Go2RTC
    final registerEndpoint =
        'http://$host:1984/api/streams?src=$encodedStream&name=$streamId';
    debugPrint('Registering stream: $registerEndpoint');

    try {
      final registerResponse = await http.put(Uri.parse(registerEndpoint));
      debugPrint('Stream Registration Status: ${registerResponse.statusCode}');
    } catch (e) {
      debugPrint('Stream Registration Warning: $e');
      // Continue anyway - stream might already exist
    }

    // Step 2: Now request WebRTC using the registered stream name
    final endpoint = 'http://$host:1984/api/webrtc?src=$streamId';
    debugPrint('WebRTC Endpoint: $endpoint');

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        body: offer.sdp, // Send the localized SDP
      );

      if (response.statusCode == 200) {
        // 5. Set Remote Description (Answer)
        final sdpAnswer = response.body;
        debugPrint('Go2RTC Response Body: $sdpAnswer'); // CRITICAL DEBUG LOG

        if (sdpAnswer.isEmpty) {
          throw Exception('Go2RTC returned empty body');
        }

        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdpAnswer, 'answer'),
        );

        return _remoteStream; // This might be empty initially until onTrack fires
      } else {
        throw Exception('Failed to connect to Go2RTC: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<void> disconnect() async {
    await _peerConnection?.close();
    _peerConnection = null;
  }
}
