import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../domain/camera_model.dart';
import '../../data/snapshot_service.dart';
import '../../../recording/data/recording_service.dart';
import 'stream_player.dart';
import '../screens/camera_settings_screen.dart';

class CameraTile extends ConsumerStatefulWidget {
  final Camera camera;
  final String host;
  final VoidCallback onRefresh;
  final Function(String) onDelete;

  const CameraTile({
    super.key,
    required this.camera,
    required this.host,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  ConsumerState<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends ConsumerState<CameraTile> {
  final _recordingService = RecordingService();
  final _snapshotService = SnapshotService();
  final _playerKey = GlobalKey<ConsumerState<StreamPlayer>>();

  bool _isRecording = false;
  bool _isActionLoading = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _checkRecordingStatus();
    // Poll status every 5 seconds to stay strictly in sync with Server
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkRecordingStatus(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkRecordingStatus() async {
    // Silent check
    try {
      final status = await _recordingService.isRecording(widget.camera.id);
      if (mounted && status != _isRecording) {
        setState(() => _isRecording = status);
      }
    } catch (e) {
      // Ignore poll errors
    }
  }

  Future<void> _toggleRecording() async {
    setState(() => _isActionLoading = true);
    try {
      if (_isRecording) {
        // STOP
        await _recordingService.stopRecording(widget.camera.id);
      } else {
        // START
        await _recordingService.startRecording(
          widget.camera.id,
          widget.camera.name,
          widget.camera.streamUrl, // Pass RTSP URL
        );
      }
      // Updates UI immediately (optimistic), timer will confirm
      setState(() => _isRecording = !_isRecording);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _takeSnapshot() async {
    try {
      // Access StreamPlayer state locally
      if (_playerKey.currentState == null) throw Exception("Player not ready");

      final dynamic state =
          _playerKey.currentState; // Cast to dynamic for method access
      // ignore: avoid_dynamic_calls
      final bytes = await state.captureSnapshot() as Uint8List?;

      if (bytes != null) {
        // Updated to pass camera name for forensic storage
        await _snapshotService.uploadSnapshot(
          widget.camera.id,
          widget.camera.name,
          bytes,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📸 Snapshot Saved: ${widget.camera.name}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Snapshot failed: $e');
    }
  }

  Future<void> _openScheduleDialog() async {
    String scheduleType = 'daily';
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay? endTime;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Schedule: ${widget.camera.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: scheduleType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'oneTime', child: Text('One Time')),
                ],
                onChanged: (v) => setDialogState(() => scheduleType = v!),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text('Start: ${startTime.format(ctx)}'),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: startTime);
                  if (t != null) setDialogState(() => startTime = t);
                },
              ),
              ListTile(
                title: Text('End: ${endTime?.format(ctx) ?? "Not set"}'),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx, initialTime: endTime ?? TimeOfDay.now());
                  if (t != null) setDialogState(() => endTime = t);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );

    if (result == true) {
      final now = DateTime.now();
      final startDt = DateTime(
          now.year, now.month, now.day, startTime.hour, startTime.minute);
      DateTime? endDt = endTime != null
          ? DateTime(
              now.year, now.month, now.day, endTime!.hour, endTime!.minute)
          : null;

      try {
        await http.post(
          Uri.parse('http://127.0.0.1:8091/schedule/add'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'camera_name': widget.camera.name,
            'camera_id': widget.camera.id,
            'rtsp_url': widget.camera.streamUrl,
            'type': scheduleType,
            'start_time': startDt.toIso8601String(),
            'end_time': endDt?.toIso8601String(),
          }),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Schedule added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _isRecording ? Colors.redAccent : Colors.grey.shade800,
          width: _isRecording ? 2 : 1, // Visual feedback for recording
        ),
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Stream Player
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: StreamPlayer(
              key: _playerKey,
              streamName: widget.camera.streamUrl,
              host: widget.host,
            ),
          ),

          // 2. Info Overlay (Top Left)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: _isRecording ? Colors.red : Colors.green,
                    size: 8,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.camera.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // 3. Manual Controls (Bottom Bar) - Professional VMS Style
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54, // Semi-transparent bar
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Record / Pause Button
                  IconButton(
                    icon: _isActionLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isRecording
                                ? Icons.stop
                                : Icons.fiber_manual_record,
                            color: _isRecording ? Colors.white : Colors.red,
                          ),
                    tooltip:
                        _isRecording ? 'Stop Recording' : 'Start Recording',
                    onPressed: _toggleRecording,
                  ),

                  // Snapshot
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt,
                      color: Colors.white70,
                      size: 20,
                    ),
                    tooltip: 'Snapshot',
                    onPressed: _takeSnapshot,
                  ),

                  // Schedule
                  IconButton(
                    icon: const Icon(
                      Icons.schedule,
                      color: Colors.white70,
                      size: 20,
                    ),
                    tooltip: 'Schedule Recording',
                    onPressed: () => _openScheduleDialog(),
                  ),

                  // Settings
                  IconButton(
                    icon: const Icon(
                      Icons.settings,
                      color: Colors.white70,
                      size: 20,
                    ),
                    tooltip: 'Settings',
                    onPressed: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CameraSettingsScreen(camera: widget.camera),
                        ),
                      );
                      if (res == true) widget.onRefresh();
                    },
                  ),

                  // Delete
                  IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    tooltip: 'Delete Camera',
                    onPressed: () => widget.onDelete(widget.camera.id),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
