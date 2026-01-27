/**
 * Scheduler Service - Time-based Recording Automation
 * VMS Phase 3: Scheduler
 * 
 * Features:
 * - One-time schedules (start at X, stop at Y)
 * - Recurring schedules (daily, weekly)
 * - Persists across restarts via scheduler_config.json
 * - Gateway-owned (no Flutter timers)
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ScheduleType { oneTime, daily, weekly }

class Schedule {
  final String id;
  final String cameraId;
  final String cameraName;
  final String rtspUrl;
  final ScheduleType type;
  final DateTime
      startTime; // For one-time: absolute; For recurring: time-of-day
  final DateTime? endTime; // Optional auto-stop
  final List<int>? weekdays; // For weekly: 1=Mon, 7=Sun
  bool isActive;

  Schedule({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.rtspUrl,
    required this.type,
    required this.startTime,
    this.endTime,
    this.weekdays,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'camera_id': cameraId,
        'camera_name': cameraName,
        'rtsp_url': rtspUrl,
        'type': type.name,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'weekdays': weekdays,
        'is_active': isActive,
      };

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        id: json['id'],
        cameraId: json['camera_id'],
        cameraName: json['camera_name'],
        rtspUrl: json['rtsp_url'],
        type: ScheduleType.values.byName(json['type']),
        startTime: DateTime.parse(json['start_time']),
        endTime:
            json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
        weekdays:
            json['weekdays'] != null ? List<int>.from(json['weekdays']) : null,
        isActive: json['is_active'] ?? true,
      );
}

class SchedulerService {
  static const _configPath = 'scheduler_config.json';

  final List<Schedule> _schedules = [];
  final Function(String cameraId, String cameraName, String rtspUrl)
      onStartRecording;
  final Function(String cameraId) onStopRecording;

  Timer? _tickTimer;

  SchedulerService({
    required this.onStartRecording,
    required this.onStopRecording,
  });

  /// Initialize and load persisted schedules
  Future<void> init() async {
    await _loadConfig();
    _startTick();
    print(
        '⏰ SchedulerService initialized with ${_schedules.length} schedule(s)');
  }

  /// Add a new schedule
  String addSchedule(Schedule schedule) {
    _schedules.add(schedule);
    _saveConfig();
    print('   + Added schedule: ${schedule.id} for ${schedule.cameraName}');
    return schedule.id;
  }

  /// Remove a schedule by ID
  bool removeSchedule(String id) {
    final before = _schedules.length;
    _schedules.removeWhere((s) => s.id == id);
    final removed = _schedules.length < before;
    if (removed) _saveConfig();
    return removed;
  }

  /// List all schedules
  List<Schedule> listSchedules() => List.unmodifiable(_schedules);

  /// Get schedules for a specific camera
  List<Schedule> getSchedulesForCamera(String cameraId) =>
      _schedules.where((s) => s.cameraId == cameraId).toList();

  // --------------- Private ---------------

  void _startTick() {
    // Tick every 5 seconds for precise timing
    _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();

    for (final schedule in _schedules) {
      if (!schedule.isActive) continue;

      switch (schedule.type) {
        case ScheduleType.oneTime:
          _checkOneTime(schedule, now);
          break;
        case ScheduleType.daily:
          _checkDaily(schedule, now);
          break;
        case ScheduleType.weekly:
          _checkWeekly(schedule, now);
          break;
      }
    }
  }

  void _checkOneTime(Schedule s, DateTime now) {
    // Start if within 1 minute of start time and not yet past end
    if (_isNearTime(now, s.startTime)) {
      onStartRecording(s.cameraId, s.cameraName, s.rtspUrl);
    }
    if (s.endTime != null && _isNearTime(now, s.endTime!)) {
      onStopRecording(s.cameraId);
      s.isActive = false; // One-time complete
      _saveConfig();
    }
  }

  void _checkDaily(Schedule s, DateTime now) {
    final todayStart = DateTime(
        now.year, now.month, now.day, s.startTime.hour, s.startTime.minute);
    if (_isNearTime(now, todayStart)) {
      onStartRecording(s.cameraId, s.cameraName, s.rtspUrl);
    }
    if (s.endTime != null) {
      final todayEnd = DateTime(
          now.year, now.month, now.day, s.endTime!.hour, s.endTime!.minute);
      if (_isNearTime(now, todayEnd)) {
        onStopRecording(s.cameraId);
      }
    }
  }

  void _checkWeekly(Schedule s, DateTime now) {
    if (s.weekdays == null || !s.weekdays!.contains(now.weekday)) return;
    _checkDaily(s, now); // Same logic as daily if today is a target day
  }

  bool _isNearTime(DateTime now, DateTime target) {
    final diff = now.difference(target).inSeconds.abs();
    return diff < 10; // Within 10 second window for precision
  }

  Future<void> _loadConfig() async {
    try {
      final file = File(_configPath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final list = json['schedules'] as List;
        _schedules.addAll(list.map((j) => Schedule.fromJson(j)));
      }
    } catch (e) {
      print('   ⚠️ Failed to load scheduler config: $e');
    }
  }

  Future<void> _saveConfig() async {
    try {
      final file = File(_configPath);
      final json = {'schedules': _schedules.map((s) => s.toJson()).toList()};
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print('   ⚠️ Failed to save scheduler config: $e');
    }
  }

  void dispose() {
    _tickTimer?.cancel();
  }
}
