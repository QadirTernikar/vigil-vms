import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vigil_app/features/dashboard/domain/camera_model.dart';
import '../../data/playback_repository.dart';
import '../../domain/models/recording.dart';
import '../controllers/timeline_controller.dart';
import '../widgets/timeline_widget.dart';

class PlaybackScreen extends ConsumerStatefulWidget {
  final Camera? camera; // Nullable for Selector Mode

  const PlaybackScreen({super.key, this.camera});

  @override
  ConsumerState<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends ConsumerState<PlaybackScreen> {
  final _repository = PlaybackRepository();

  // MediaKit
  late final Player _player;
  late final VideoController _videoController;

  // Timeline
  late final TimelineController _timelineController;
  Timer? _positionTimer;

  // State
  List<Recording> _recordings = [];
  Recording? _currentRecording;

  String? _selectedCameraName; // Drives Logic
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  bool _isLoadingList = false;
  String? _errorMessage;
  bool _isGatewayOnline = false;

  List<String> _availableCameras = []; // For Selector

  // UI State
  DateTime _uiTime = DateTime.now();

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    // 1. Initialize Player
    _player = Player();
    _videoController = VideoController(_player);

    // 2. Initialize Timeline
    _timelineController = TimelineController(
      initialTime: DateTime.now(),
      onTimeChanged: (time) {
        if (mounted) setState(() => _uiTime = time);
      },
    );

    // 3. Listeners
    _player.stream.error.listen((error) {
      if (mounted) setState(() => _errorMessage = 'Playback Error: $error');
    });

    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_player.state.playing && _currentRecording != null) {
        final position = _player.state.position;
        final duration = _player.state.duration;
        final actualTime = _currentRecording!.startTime.add(position);
        _timelineController.updateTime(actualTime);

        // PRE-BUFFERING: At 80% of segment, pre-load next URL
        if (duration.inMilliseconds > 0 &&
            position.inMilliseconds > duration.inMilliseconds * 0.8 &&
            _prebufferedNextUrl == null) {
          _prebufferNextSegment();
        }
      }
    });

    // POLLING: Refresh recordings every 10s to show new segments
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_selectedCameraName != null && isToday(_selectedDate)) {
        _loadRecordings(silent: true);
      }
    });

    _player.stream.completed.listen((completed) {
      if (completed && mounted) _handlePlaybackCompletion();
    });

    _checkGateway();

    // 4. Initial Load
    if (widget.camera != null) {
      _selectedCameraName = widget.camera!.name;
      _loadRecordings();
    } else {
      _loadAvailableCameras();
    }
  }

  // Pre-buffer next segment URL for seamless transition
  String? _prebufferedNextUrl;
  Recording? _prebufferedNextRecording;

  void _prebufferNextSegment() {
    if (_currentRecording == null) return;
    final next = _timelineController.getNextRecording(_currentRecording!);
    if (next != null) {
      final gap = next.startTime.difference(_currentRecording!.endTime);
      if (gap <= const Duration(seconds: 5)) {
        _prebufferedNextUrl = _repository.getPlaybackUrl(next);
        _prebufferedNextRecording = next;
      }
    }
  }

  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _loadAvailableCameras() async {
    setState(() => _isLoadingList = true);
    final cameras = await _repository.getAvailablePlaybackCameras();
    setState(() {
      _availableCameras = cameras;
      _isLoadingList = false;
    });
  }

  void _handlePlaybackCompletion() async {
    if (_currentRecording == null) {
      debugPrint('🔄 PlaybackCompletion: No current recording');
      return;
    }

    debugPrint('🔄 PlaybackCompletion: Current=${_currentRecording!.id}');

    final next = _timelineController.getNextRecording(_currentRecording!);
    debugPrint('🔄 PlaybackCompletion: Next=${next?.id ?? "NULL"}');

    if (next == null) {
      _prebufferedNextUrl = null;
      _prebufferedNextRecording = null;
      // Only stop if truly at end
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("End of recording timeline.")),
        );
      }
      return;
    }

    // Calculate gap duration
    final gap = next.startTime.difference(_currentRecording!.endTime);
    debugPrint('🔄 PlaybackCompletion: Gap=${gap.inSeconds}s');

    if (gap > const Duration(seconds: 5)) {
      // GAP DETECTED - PAUSE AND PROMPT (don't stop to avoid black screen)
      _prebufferedNextUrl = null;
      _prebufferedNextRecording = null;
      await _player.pause();
      if (mounted) _showGapDialog(gap, next);
    } else {
      // SEAMLESS TRANSITION - use prebuffered URL if available
      String url;
      if (_prebufferedNextUrl != null &&
          _prebufferedNextRecording?.id == next.id) {
        url = _prebufferedNextUrl!;
        debugPrint('🔄 Using prebuffered URL');
      } else {
        url = _repository.getPlaybackUrl(next);
        debugPrint('🔄 Fetching new URL');
      }

      // Reset prebuffer state
      _prebufferedNextUrl = null;
      _prebufferedNextRecording = null;

      // Update state BEFORE opening to prevent flicker
      setState(() => _currentRecording = next);

      // Open immediately without stopping - continuous playback
      await _player.open(Media(url), play: true);
      debugPrint('🔄 Seamless transition complete');
    }
  }

  void _showGapDialog(Duration gap, Recording next) {
    final minutes = gap.inMinutes;
    final seconds = gap.inSeconds % 60;
    final gapStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Gap Detected'),
        content: Text(
            'There is a $gapStr gap in the recording.\nJump to next segment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay Here'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onTimelineSeek(next.startTime);
            },
            child: const Text('Jump to Next'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _positionTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _checkGateway() async {
    final isOnline = await _repository.isGatewayOnline();
    if (mounted) setState(() => _isGatewayOnline = isOnline);
  }

  Future<void> _loadRecordings({bool silent = false}) async {
    if (_selectedCameraName == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _recordings = [];
        _currentRecording = null;
      });
    }

    try {
      final recordings = await _repository.getRecordingsByDate(
        cameraName: _selectedCameraName!,
        date: _selectedDate,
      );

      _timelineController.setRecordings(recordings);

      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });

      if (recordings.isEmpty)
        setState(
          () => _errorMessage = 'No recordings found for $_selectedDate',
        );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load metadata: $e';
      });
    }
  }

  Future<void> _onTimelineSeek(DateTime targetTime) async {
    await _player.pause();
    _timelineController.updateTime(targetTime);
    final target = _timelineController.getSeekTargetFor(targetTime);

    if (target == null) {
      await _player.stop();
      setState(() {
        _currentRecording = null;
        _errorMessage = "No Recording at this time";
      });
      return;
    }

    setState(() => _errorMessage = null);
    if (_currentRecording?.id != target.recording.id) {
      final url = _repository.getPlaybackUrl(target.recording);
      await _player.open(Media(url), play: false);
      setState(() => _currentRecording = target.recording);
    }
    await _player.seek(target.offset);
    await _player.play();
  }

  void _jumpToNextSegment() {
    if (_currentRecording == null) return;
    final next = _timelineController.getNextRecording(_currentRecording!);
    if (next != null) {
      _onTimelineSeek(next.startTime);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No next segment found.")),
      );
    }
  }

  void _jumpToPreviousSegment() {
    if (_currentRecording == null) return;
    final prev = _timelineController.getPreviousRecording(_currentRecording!);
    if (prev != null) {
      _onTimelineSeek(prev.startTime);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No previous segment found.")),
      );
    }
  }

  void _skip10sForward() {
    final newTime = _uiTime.add(const Duration(seconds: 10));
    final target = _timelineController.getSeekTargetFor(newTime);

    if (target != null) {
      // Target is within a segment
      _onTimelineSeek(newTime);
    } else {
      // Target is in a gap - find next segment
      final next = _timelineController.getRecordingAtOrAfter(newTime);
      if (next != null) {
        _onTimelineSeek(next.startTime);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No more recordings ahead.")),
        );
      }
    }
  }

  void _skip10sBackward() {
    final newTime = _uiTime.subtract(const Duration(seconds: 10));
    final target = _timelineController.getSeekTargetFor(newTime);

    if (target != null) {
      // Target is within a segment
      _onTimelineSeek(newTime);
    } else {
      // Target is in a gap - find previous segment end
      final prev = _timelineController.getRecordingBefore(newTime);
      if (prev != null) {
        // Seek to near end of previous segment
        final seekTime = prev.endTime.subtract(const Duration(seconds: 1));
        _onTimelineSeek(seekTime);
      } else {
        // Try to go to start of first recording
        final recordings = _timelineController.recordings;
        if (recordings.isNotEmpty) {
          _onTimelineSeek(recordings.first.startTime);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No earlier recordings.")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // SELECTOR MODE
    if (_selectedCameraName == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Select Evidence Source')),
        body: _isLoadingList
            ? const Center(child: CircularProgressIndicator())
            : _availableCameras.isEmpty
                ? const Center(child: Text("No recordings available."))
                : ListView.builder(
                    itemCount: _availableCameras.length,
                    itemBuilder: (ctx, i) => ListTile(
                      leading: const Icon(Icons.videocam),
                      title: Text(_availableCameras[i]),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        setState(() {
                          _selectedCameraName = _availableCameras[i];
                          _loadRecordings();
                        });
                      },
                    ),
                  ),
      );
    }

    // PLAYBACK MODE
    return Scaffold(
      appBar: AppBar(
        title: Text('Forensic Playback: $_selectedCameraName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_video),
            tooltip: 'Switch Camera',
            onPressed: () {
              setState(() {
                _selectedCameraName = null;
                _loadAvailableCameras();
              });
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkGateway),
        ],
      ),
      body: Column(
        children: [
          if (!_isGatewayOnline)
            Container(
              color: Colors.red,
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              child: const Text(
                'Gateway Offline',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _currentRecording != null
                    ? Video(controller: _videoController)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_off,
                            color: Colors.grey,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage ?? 'Select a time on the timeline',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text(
                        "Cam: $_selectedCameraName",
                        style: const TextStyle(color: Colors.white),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(
                          Icons.calendar_today,
                          color: Colors.white70,
                        ),
                        label: Text(
                          "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}",
                          style: const TextStyle(color: Colors.white),
                        ),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) {
                            setState(() => _selectedDate = d);
                            _loadRecordings();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  color: Colors.black26,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Back 10s
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        tooltip: 'Back 10s',
                        onPressed: _skip10sBackward,
                      ),
                      // Previous Segment
                      IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white),
                        tooltip: 'Previous Recording',
                        onPressed: _jumpToPreviousSegment,
                      ),
                      const SizedBox(width: 16),
                      // Next Segment
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        tooltip: 'Next Recording',
                        onPressed: _jumpToNextSegment,
                      ),
                      // Skip 10s
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        tooltip: 'Skip 10s',
                        onPressed: _skip10sForward,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 100,
                  child: _recordings.isEmpty && _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TimelineWidget(
                          recordings: _recordings,
                          currentTime: _uiTime,
                          onSeek: _onTimelineSeek,
                          onScrubUpdate: (time) =>
                              _timelineController.updateTime(time),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
