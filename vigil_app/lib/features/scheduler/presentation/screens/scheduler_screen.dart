import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});
  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  static const String _baseUrl = 'http://127.0.0.1:8091';
  List<Map<String, dynamic>> _schedules = [];
  List<String> _cameras = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load schedules
      final schedRes = await http.get(Uri.parse('$_baseUrl/schedule/list'));
      if (schedRes.statusCode == 200) {
        final data = jsonDecode(schedRes.body);
        _schedules = List<Map<String, dynamic>>.from(data['schedules'] ?? []);
      }
      // Load cameras from queue
      final camRes =
          await http.get(Uri.parse('$_baseUrl/record/queue/segments'));
      if (camRes.statusCode == 200) {
        final data = jsonDecode(camRes.body);
        final segments = data['segments'] as List? ?? [];
        final names = segments
            .map((s) => s['camera_name'] as String?)
            .whereType<String>()
            .toSet();
        _cameras = names.toList()..sort();
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _addSchedule() async {
    String? selectedCamera;
    String scheduleType = 'daily';
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay? endTime;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedCamera,
                hint: const Text('Select Camera'),
                items: _cameras
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedCamera = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: scheduleType,
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
              onPressed: selectedCamera == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedCamera != null) {
      final now = DateTime.now();
      final startDt = DateTime(
          now.year, now.month, now.day, startTime.hour, startTime.minute);
      DateTime? endDt = endTime != null
          ? DateTime(
              now.year, now.month, now.day, endTime!.hour, endTime!.minute)
          : null;

      await http.post(
        Uri.parse('$_baseUrl/schedule/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'camera_name': selectedCamera,
          'camera_id': selectedCamera,
          'rtsp_url': '',
          'type': scheduleType,
          'start_time': startDt.toIso8601String(),
          'end_time': endDt?.toIso8601String(),
        }),
      );
      _loadData();
    }
  }

  Future<void> _deleteSchedule(String id) async {
    await http.delete(Uri.parse('$_baseUrl/schedule/remove?id=$id'));
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recording Schedules')),
      floatingActionButton: FloatingActionButton(
          onPressed: _addSchedule, child: const Icon(Icons.add)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
              ? const Center(child: Text('No schedules. Tap + to add.'))
              : ListView.builder(
                  itemCount: _schedules.length,
                  itemBuilder: (ctx, i) {
                    final s = _schedules[i];
                    return ListTile(
                      leading: Icon(
                          s['type'] == 'daily' ? Icons.repeat : Icons.schedule),
                      title: Text(s['camera_name'] ?? 'Unknown'),
                      subtitle: Text(
                          '${s['type']} • ${_formatTime(s['start_time'])}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteSchedule(s['id'].toString()),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
