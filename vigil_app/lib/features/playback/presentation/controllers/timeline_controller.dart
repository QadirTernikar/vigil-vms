import 'package:vigil_app/features/playback/domain/models/recording.dart';

/// Mapping result containing the target file and the precise start offset.
class SeekTarget {
  final Recording recording;
  final Duration offset;

  SeekTarget({required this.recording, required this.offset});
}

/// Controller responsible for forensic timeline logic.
/// STRICT RULE: No guessing, no interpolation. Data truth only.
class TimelineController {
  // Sorted list of recordings for the current day.
  List<Recording> _recordings = [];

  // Current selected time (UTC).
  DateTime _currentTime;

  // Callback to update UI when time changes.
  final Function(DateTime) onTimeChanged;

  TimelineController({
    required DateTime initialTime,
    required this.onTimeChanged,
  }) : _currentTime = initialTime;

  /// Loads new recording data. Data must be sorted by startTime.
  void setRecordings(List<Recording> recordings) {
    // Ensure chronological sort for binary search (though simple iteration is fine for daily count)
    _recordings = List.of(recordings)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Returns the current selected time.
  DateTime get currentTime => _currentTime;

  /// Updates the current time (e.g., during scrub).
  /// This does NOT trigger playback seek, only UI update.
  void updateTime(DateTime newTime) {
    _currentTime = newTime;
    onTimeChanged(newTime);
  }

  /// Calculates the precise file and offset for the current time.
  /// Returns [SeekTarget] if within a segment.
  /// Returns [null] if in a gap.
  SeekTarget? getSeekTarget() {
    return _findSegment(_currentTime);
  }

  /// Calculates the precise file and offset for a specific target time.
  /// Used for jump-to-time actions.
  SeekTarget? getSeekTargetFor(DateTime targetTime) {
    return _findSegment(targetTime);
  }

  /// Core Logic: Finds the segment covering the given time.
  /// Returns null if time falls in a gap.
  SeekTarget? _findSegment(DateTime time) {
    // Linear search is efficient enough for typical CCTV daily segment counts (< 5000)

    for (final recording in _recordings) {
      // Inclusive start (>=), exclusive end (<)
      // This is standard VMS behavior: segment owns [start, end)
      final isAfterOrAtStart = !time.isBefore(recording.startTime);
      final isBeforeEnd = time.isBefore(recording.endTime);

      if (isAfterOrAtStart && isBeforeEnd) {
        final offset = time.difference(recording.startTime);
        return SeekTarget(recording: recording, offset: offset);
      }

      // Edge case: Exactly at end time -> clamp to last frame
      if (time.isAtSameMomentAs(recording.endTime)) {
        return SeekTarget(
          recording: recording,
          offset: recording.endTime.difference(recording.startTime),
        );
      }
    }

    return null; // Time is in a GAP.
  }

  /// Checks if there is a gap at the given time.
  bool isGap(DateTime time) {
    return _findSegment(time) == null;
  }

  /// Get all recordings
  List<Recording> get recordings => _recordings;

  /// Get the next recording in the timeline (for "Next Segment" button)
  /// Uses ID-based matching to handle object reference mismatches
  Recording? getNextRecording(Recording current) {
    final index = _recordings.indexWhere((r) => r.id == current.id);
    if (index >= 0 && index < _recordings.length - 1) {
      return _recordings[index + 1];
    }
    return null;
  }

  /// Get the previous recording in the timeline (for "Previous Segment" button)
  /// Uses ID-based matching to handle object reference mismatches
  Recording? getPreviousRecording(Recording current) {
    final index = _recordings.indexWhere((r) => r.id == current.id);
    if (index > 0) {
      return _recordings[index - 1];
    }
    return null;
  }

  /// Get the recording that contains a specific time, or the next one if in gap
  Recording? getRecordingAtOrAfter(DateTime time) {
    // First try exact match
    final exact = _findSegment(time);
    if (exact != null) return exact.recording;

    // If in gap, find next segment
    for (final recording in _recordings) {
      if (recording.startTime.isAfter(time)) {
        return recording;
      }
    }
    return null;
  }

  /// Get the recording before a specific time (for backward skip into gap)
  Recording? getRecordingBefore(DateTime time) {
    Recording? last;
    for (final recording in _recordings) {
      if (recording.endTime.isBefore(time) ||
          recording.endTime.isAtSameMomentAs(time)) {
        last = recording;
      } else {
        break;
      }
    }
    return last;
  }
}
