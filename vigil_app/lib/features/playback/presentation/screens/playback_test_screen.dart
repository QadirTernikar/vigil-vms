/**
 * Playback Test Screen
 * M6-3: Playback API
 * 
 * Simple test UI for validating M6-3 requirements:
 * - Query recordings from Supabase
 * - Play from Gateway (using MediaKit for Windows support)
 * - Handle errors
 * - Deterministic playback
 * 
 * SECURITY NOTE: No authentication in M6-3. Added in M6-7.
 */

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/playback_repository.dart';
import '../../domain/models/recording.dart';

class PlaybackTestScreen extends StatefulWidget {
  const PlaybackTestScreen({super.key});

  @override
  State<PlaybackTestScreen> createState() => _PlaybackTestScreenState();
}

class _PlaybackTestScreenState extends State<PlaybackTestScreen> {
  final PlaybackRepository _repository = PlaybackRepository();

  // MediaKit Controllers
  late final Player _player;
  late final VideoController _videoController;

  List<Recording> _recordings = [];
  Recording? _currentRecording;

  String _selectedCamera = 'bunny';
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  String? _errorMessage;
  bool _isGatewayOnline = false;

  @override
  void initState() {
    super.initState();
    // Initialize MediaKit Player
    _player = Player();
    _videoController = VideoController(_player);

    // Listen for errors
    _player.stream.error.listen((error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Playback Error: $error';
          _isLoading = false;
        });
      }
    });

    _checkGateway();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _checkGateway() async {
    final isOnline = await _repository.isGatewayOnline();
    if (mounted) {
      setState(() {
        _isGatewayOnline = isOnline;
      });
    }
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _recordings = [];
      _currentRecording = null;
    });

    try {
      final recordings = await _repository.getRecordingsByDate(
        cameraName: _selectedCamera,
        date: _selectedDate,
      );

      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });

      if (recordings.isEmpty) {
        setState(() {
          _errorMessage = 'No recordings found for this date';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load recordings: $e';
      });
    }
  }

  Future<void> _playRecording(Recording recording) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Build playback URL (Gateway, not Supabase)
      final url = _repository.getPlaybackUrl(recording);

      // Open media
      await _player.open(Media(url));

      setState(() {
        _currentRecording = recording;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to start playback: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M6-3 Playback Test (MediaKit)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkGateway,
            tooltip: 'Check Gateway',
          ),
        ],
      ),
      body: Column(
        children: [
          // Gateway status
          Container(
            color: _isGatewayOnline ? Colors.green : Colors.red,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(
                  _isGatewayOnline ? Icons.check_circle : Icons.error,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  _isGatewayOnline
                      ? 'Gateway Online'
                      : 'Gateway Offline - Start playback_server.dart',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Camera selector
                DropdownButton<String>(
                  value: _selectedCamera,
                  items: const [
                    DropdownMenuItem(value: 'bunny', child: Text('Bunny')),
                    DropdownMenuItem(
                      value: 'cam_445791032',
                      child: Text('Camera 445791032'),
                    ),
                    DropdownMenuItem(
                      value: 'cam_892175943',
                      child: Text('Camera 892175943'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCamera = value;
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Date picker
                ElevatedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    'Date: ${_selectedDate.toString().split(' ')[0]}',
                  ),
                ),

                const SizedBox(height: 16),

                // Load button
                ElevatedButton(
                  onPressed: _isLoading ? null : _loadRecordings,
                  child: const Text('Load Recordings'),
                ),
              ],
            ),
          ),

          // Error message
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          // Video player Area
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _currentRecording != null
                    ? Video(controller: _videoController)
                    : const Text(
                        'Select a recording to play',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ),

          // Recording list
          if (_recordings.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _recordings.length,
                itemBuilder: (context, index) {
                  final recording = _recordings[index];
                  final isPlaying = _currentRecording?.id == recording.id;

                  return ListTile(
                    leading: Icon(
                      isPlaying ? Icons.play_circle : Icons.videocam,
                      color: isPlaying ? Colors.blue : null,
                    ),
                    title: Text(recording.startTime.toLocal().toString()),
                    subtitle: Text('${recording.durationSeconds.toInt()}s'),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _playRecording(recording),
                    ),
                    selected: isPlaying,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
