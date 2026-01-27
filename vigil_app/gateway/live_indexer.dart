import 'package:supabase/supabase.dart';
import 'index_queue.dart';

/// Supabase configuration
class SupabaseConfig {
  static const String url = 'https://vblpuewnntphpfizozgh.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZibHB1ZXdubnRwaHBmaXpvemZnaCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzM5MTgyNzE5LCJleHAiOjIwNTQ3NTg3MTl9.wH9rNBg1JdB_3T9zIxlBcxp02bMN1W7oXhwh2NgqFNw';
}

/// Resilient Live Indexer
///
/// Architecture:
/// 1. On segment close → Write to LOCAL queue (immediate, never fails)
/// 2. Background worker → Syncs to Supabase when available
/// 3. Recording NEVER blocked by cloud
class ResilientIndexer {
  late final SupabaseClient _supabase;
  final IndexQueue _queue;
  final int segmentDuration;
  bool _initialized = false;

  ResilientIndexer({
    required IndexQueue queue,
    this.segmentDuration = 10,
  }) : _queue = queue {
    _supabase = SupabaseClient(
      SupabaseConfig.url,
      SupabaseConfig.anonKey,
    );
  }

  /// Initialize indexer and start background sync
  Future<void> init() async {
    if (_initialized) return;

    await _queue.init();

    // Start background sync worker
    _queue.startSyncWorker(_syncToSupabase, interval: Duration(seconds: 5));

    _initialized = true;
    print('📊 Resilient Indexer initialized');
  }

  /// Queue a segment for indexing (LOCAL FIRST - never fails)
  Future<void> queueSegment({
    required String cameraId,
    required String cameraName,
    required String filePath,
    required String fileName,
    required DateTime startTime,
    required int fileSize,
  }) async {
    final endTime = startTime.add(Duration(seconds: segmentDuration));

    final segment = PendingSegment(
      cameraId: cameraId,
      cameraName: cameraName,
      filePath: filePath,
      fileName: fileName,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: segmentDuration,
      fileSize: fileSize,
    );

    // This NEVER fails - writes to local disk
    await _queue.enqueue(segment);

    // Attempt immediate sync (but don't block on failure)
    _trySyncImmediate(segment);
  }

  /// Try to sync immediately (non-blocking)
  void _trySyncImmediate(PendingSegment segment) {
    _syncToSupabase(segment).then((success) {
      if (success) {
        _queue.markSynced(segment.filePath);
      }
    }).catchError((e) {
      // Ignore - background worker will retry
    });
  }

  /// Sync a segment to Supabase
  Future<bool> _syncToSupabase(PendingSegment segment) async {
    try {
      // Check if already exists (idempotency)
      final existing = await _supabase
          .from('recordings')
          .select('id')
          .eq('file_path', segment.filePath)
          .maybeSingle();

      if (existing != null) {
        print('   ℹ️ Already synced: ${segment.fileName}');
        return true;
      }

      // Insert
      await _supabase.from('recordings').insert({
        'camera_id': segment.cameraId,
        'camera_name': segment.cameraName,
        'file_path': segment.filePath,
        'start_time': segment.startTime.toIso8601String(),
        'end_time': segment.endTime.toIso8601String(),
        'duration_seconds': segment.durationSeconds,
      });

      print('   ☁️ Synced to cloud: ${segment.fileName}');
      return true;
    } catch (e) {
      print('   ⚠️ Sync failed: $e');
      return false;
    }
  }

  /// Get all local segments for a camera (for offline playback)
  List<PendingSegment> getLocalSegments(String cameraId) {
    return _queue.forCamera(cameraId);
  }

  /// Get ALL local segments (for admin/debug)
  List<PendingSegment> getLocalSegmentsAll() {
    return _queue.all;
  }

  /// Get queue status
  Map<String, dynamic> getStatus() {
    return _queue.getStatus();
  }

  /// Stop indexer
  void stop() {
    _queue.stopSyncWorker();
  }
}
