/**
 * Recording Model
 * M6-3: Playback API
 * 
 * Represents metadata for a single recording segment.
 * Data comes from Supabase `recordings` table.
 */

class Recording {
  final String id;
  final String cameraId;
  final String cameraName; // Added M6-5 Professional
  final String filePath;
  final DateTime startTime;
  final DateTime endTime;
  final double durationSeconds;
  final DateTime? createdAt;

  Recording({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.createdAt,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      cameraId: json['camera_id'] as String,
      cameraName: json['camera_name'] as String? ?? 'Unknown',
      filePath: json['file_path'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'camera_id': cameraId,
      'camera_name': cameraName,
      'file_path': filePath,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration_seconds': durationSeconds,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'Recording(id: $id, camera: $cameraId, start: $startTime)';
  }
}
