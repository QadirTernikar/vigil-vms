import 'dart:async';
import 'dart:io';

/// Watches a directory for new MP4 segment files
/// Emits events when a segment file is closed (ready for indexing)
class SegmentWatcher {
  final String directoryPath;
  final void Function(SegmentClosedEvent) onSegmentClosed;

  StreamSubscription<FileSystemEvent>? _subscription;
  final Set<String> _processedFiles = {};

  SegmentWatcher({
    required this.directoryPath,
    required this.onSegmentClosed,
  });

  /// Start watching for new segment files
  void start() {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    print('   👁️ Watching: $directoryPath');

    _subscription = dir
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
        .where((event) => event.path.endsWith('.mp4'))
        .listen(_handleFileEvent);
  }

  /// Stop watching
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    print('   🛑 Stopped watching: $directoryPath');
  }

  Future<void> _handleFileEvent(FileSystemEvent event) async {
    final filePath = event.path;

    // Skip if already processed
    if (_processedFiles.contains(filePath)) return;

    // Wait for file to be fully written
    // FFmpeg writes in chunks, we wait for file to stabilize
    await Future.delayed(Duration(milliseconds: 800));

    final file = File(filePath);
    if (!await file.exists()) return;

    // Check file size - must be non-zero
    final stat = await file.stat();
    if (stat.size < 1000) return; // Too small, probably still writing

    // Mark as processed
    _processedFiles.add(filePath);

    // Parse timestamp from filename (HH-MM-SS.mp4)
    final fileName = file.uri.pathSegments.last;
    final dateFolder = file.parent.uri.pathSegments
        .lastWhere((s) => s.isNotEmpty && s.contains('-'));

    print('   📄 Segment closed: $fileName (${stat.size} bytes)');

    onSegmentClosed(SegmentClosedEvent(
      filePath: filePath,
      fileName: fileName,
      dateFolder: dateFolder,
      fileSize: stat.size,
      detectedAt: DateTime.now(),
    ));
  }

  /// Clear processed files cache (for long-running sessions)
  void clearCache() {
    _processedFiles.clear();
  }
}

/// Event emitted when a segment file is closed and ready for indexing
class SegmentClosedEvent {
  final String filePath;
  final String fileName;
  final String dateFolder;
  final int fileSize;
  final DateTime detectedAt;

  SegmentClosedEvent({
    required this.filePath,
    required this.fileName,
    required this.dateFolder,
    required this.fileSize,
    required this.detectedAt,
  });

  /// Parse start time from filename (HH-MM-SS.mp4) and date folder (YYYY-MM-DD)
  DateTime get startTime {
    try {
      // Date folder: 2026-01-23
      final dateParts = dateFolder.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Filename: 14-30-00.mp4
      final timePart = fileName.replaceAll('.mp4', '');
      final timeParts = timePart.split('-');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      print('   ⚠️ Failed to parse timestamp: $e');
      return DateTime.now();
    }
  }
}
