import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local Index Queue - Resilient segment metadata storage
///
/// Architecture:
/// 1. Segment closes → Write to local queue (immediate, never fails)
/// 2. Background worker → Syncs to Supabase
/// 3. On sync success → Mark as synced
/// 4. On sync failure → Retry later
///
/// Recording NEVER blocked by cloud availability.
class IndexQueue {
  final String queueDir;
  final String queueFile;

  List<PendingSegment> _queue = [];
  bool _isRunning = false;
  Timer? _syncTimer;

  IndexQueue({String? directory})
      : queueDir = directory ?? 'go2rtc/index_queue',
        queueFile =
            '${directory ?? 'go2rtc/index_queue'}/pending_segments.json';

  /// Initialize queue - load from disk
  Future<void> init() async {
    final dir = Directory(queueDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _loadFromDisk();
    print('📋 Index Queue initialized (${_queue.length} pending)');
  }

  /// Add a segment to the queue (LOCAL FIRST - never fails)
  Future<void> enqueue(PendingSegment segment) async {
    _queue.add(segment);
    await _saveToDisk();
    print('   📥 Queued: ${segment.fileName} (${_queue.length} pending)');
  }

  /// Get all pending segments
  List<PendingSegment> get pending =>
      _queue.where((s) => s.status == SyncStatus.pending).toList();

  /// Get all segments (for local playback)
  List<PendingSegment> get all => List.from(_queue);

  /// Get segments for a specific camera
  List<PendingSegment> forCamera(String cameraId) =>
      _queue.where((s) => s.cameraId == cameraId).toList();

  /// Mark segment as synced
  Future<void> markSynced(String filePath) async {
    final segment = _queue.firstWhere(
      (s) => s.filePath == filePath,
      orElse: () => throw Exception('Segment not found: $filePath'),
    );
    segment.status = SyncStatus.synced;
    segment.syncedAt = DateTime.now();
    await _saveToDisk();
    print('   ✅ Synced: ${segment.fileName}');
  }

  /// Mark segment as failed (will retry)
  Future<void> markFailed(String filePath, String error) async {
    final segment = _queue.firstWhere(
      (s) => s.filePath == filePath,
      orElse: () => throw Exception('Segment not found: $filePath'),
    );
    segment.status = SyncStatus.failed;
    segment.lastError = error;
    segment.retryCount++;
    await _saveToDisk();
    print(
        '   ⚠️ Sync failed: ${segment.fileName} (retry ${segment.retryCount})');
  }

  /// Start background sync worker
  void startSyncWorker(
    Future<bool> Function(PendingSegment) syncFn, {
    Duration interval = const Duration(seconds: 5),
  }) {
    if (_isRunning) return;
    _isRunning = true;

    print('🔄 Index sync worker started (every ${interval.inSeconds}s)');

    _syncTimer = Timer.periodic(interval, (_) async {
      await _processPending(syncFn);
    });

    // Also run immediately
    _processPending(syncFn);
  }

  /// Stop background worker
  void stopSyncWorker() {
    _syncTimer?.cancel();
    _isRunning = false;
    print('⏹️ Index sync worker stopped');
  }

  Future<void> _processPending(
      Future<bool> Function(PendingSegment) syncFn) async {
    final toSync = pending.where((s) => s.retryCount < 10).toList();

    if (toSync.isEmpty) return;

    print('🔄 Syncing ${toSync.length} pending segments...');

    for (final segment in toSync) {
      try {
        final success = await syncFn(segment);
        if (success) {
          await markSynced(segment.filePath);
        } else {
          await markFailed(segment.filePath, 'Sync returned false');
        }
      } catch (e) {
        await markFailed(segment.filePath, e.toString());
      }
    }
  }

  /// Clean up old synced segments (keep last 24 hours)
  Future<void> cleanup({Duration maxAge = const Duration(hours: 24)}) async {
    final cutoff = DateTime.now().subtract(maxAge);
    _queue.removeWhere((s) =>
        s.status == SyncStatus.synced &&
        s.syncedAt != null &&
        s.syncedAt!.isBefore(cutoff));
    await _saveToDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = File(queueFile);
      if (await file.exists()) {
        final json = await file.readAsString();
        final list = jsonDecode(json) as List;
        _queue = list.map((e) => PendingSegment.fromJson(e)).toList();
      }
    } catch (e) {
      print('⚠️ Failed to load queue: $e');
      _queue = [];
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = File(queueFile);
      final json = jsonEncode(_queue.map((e) => e.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      print('⚠️ Failed to save queue: $e');
    }
  }

  /// Get queue status
  Map<String, dynamic> getStatus() {
    return {
      'total': _queue.length,
      'pending': _queue.where((s) => s.status == SyncStatus.pending).length,
      'synced': _queue.where((s) => s.status == SyncStatus.synced).length,
      'failed': _queue.where((s) => s.status == SyncStatus.failed).length,
      'is_running': _isRunning,
    };
  }
}

enum SyncStatus { pending, synced, failed }

/// A segment waiting to be indexed
class PendingSegment {
  final String cameraId;
  final String cameraName;
  final String filePath;
  final String fileName;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final int fileSize;
  final DateTime createdAt;

  SyncStatus status;
  DateTime? syncedAt;
  String? lastError;
  int retryCount;

  PendingSegment({
    required this.cameraId,
    required this.cameraName,
    required this.filePath,
    required this.fileName,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.fileSize,
    DateTime? createdAt,
    this.status = SyncStatus.pending,
    this.syncedAt,
    this.lastError,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'camera_id': cameraId,
        'camera_name': cameraName,
        'file_path': filePath,
        'file_name': fileName,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration_seconds': durationSeconds,
        'file_size': fileSize,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'synced_at': syncedAt?.toIso8601String(),
        'last_error': lastError,
        'retry_count': retryCount,
      };

  factory PendingSegment.fromJson(Map<String, dynamic> json) => PendingSegment(
        cameraId: json['camera_id'],
        cameraName: json['camera_name'],
        filePath: json['file_path'],
        fileName: json['file_name'],
        startTime: DateTime.parse(json['start_time']),
        endTime: DateTime.parse(json['end_time']),
        durationSeconds: json['duration_seconds'],
        fileSize: json['file_size'],
        createdAt: DateTime.parse(json['created_at']),
        status: SyncStatus.values.firstWhere((e) => e.name == json['status']),
        syncedAt: json['synced_at'] != null
            ? DateTime.parse(json['synced_at'])
            : null,
        lastError: json['last_error'],
        retryCount: json['retry_count'] ?? 0,
      );
}
