import 'package:flutter/material.dart';
import '../../domain/models/recording.dart';

class TimelineWidget extends StatefulWidget {
  final List<Recording> recordings;
  final DateTime currentTime;
  final Function(DateTime) onSeek;
  final Function(DateTime) onScrubUpdate; // To update UI while dragging

  const TimelineWidget({
    super.key,
    required this.recordings,
    required this.currentTime,
    required this.onSeek,
    required this.onScrubUpdate,
  });

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final newTime = _pixelToTime(
              details.localPosition.dx,
              constraints.maxWidth,
            );
            widget.onScrubUpdate(newTime);
          },
          onHorizontalDragEnd: (details) {
            // Note: We use the *current* drawn time (from scrub update) or recalculate?
            // Safer to track drag position, but for stateless simplicity, we can't easily recall last drag pos here without state.
            // Actually, `onScrubUpdate` pushed time to parent. Parent updated `currentTime`.
            // So onRelease, we just confirm "Seek" to that time.
            widget.onSeek(widget.currentTime);
          },
          onTapUp: (details) {
            final newTime = _pixelToTime(
              details.localPosition.dx,
              constraints.maxWidth,
            );
            widget.onSeek(newTime);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, 80),
            painter: _TimelinePainter(
              recordings: widget.recordings,
              currentTime: widget.currentTime,
            ),
          ),
        );
      },
    );
  }

  DateTime _pixelToTime(double x, double width) {
    // Clamp x
    final clampedX = x.clamp(0.0, width);

    // Map 0..width to 0..24h (in seconds)
    final totalSeconds = 24 * 3600;
    final pct = clampedX / width;
    final secondsFromMidnight = (pct * totalSeconds).round();

    // Construct DateTime for the *same day* as currentTime
    // This assumes the timeline shows "Current Day".
    // M6-4 Requirement: "Date-based navigation". Timeline shows one selected day.

    final base = DateTime(
      widget.currentTime.year,
      widget.currentTime.month,
      widget.currentTime.day,
    );

    return base.add(Duration(seconds: secondsFromMidnight));
  }
}

class _TimelinePainter extends CustomPainter {
  final List<Recording> recordings;
  final DateTime currentTime;

  _TimelinePainter({required this.recordings, required this.currentTime});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Background (The "Gap" Color)
    final bgPaint = Paint()..color = Colors.grey.shade900;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Draw Time Axis (Hour markers)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final linePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    final secondsPerPixel = (24 * 3600) / size.width;

    for (int hour = 0; hour <= 24; hour++) {
      final x = (hour * 3600) / secondsPerPixel;

      // Draw line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      // Draw Label (every 4 hours to avoid clutter, or maybe 2)
      if (hour % 4 == 0) {
        textPainter.text = TextSpan(
          text: '$hour:00',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 5));
      }
    }

    // 3. Draw Segments (The "Data" Color)
    final segmentPaint = Paint()..color = Colors.blueAccent.withOpacity(0.7);

    // Base time for the day (00:00:00)
    final startOfDay = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final endOfDay = startOfDay.add(const Duration(hours: 24));

    for (final rec in recordings) {
      // Clip segments to today's bounds (just in case)
      var effectiveStart = rec.startTime.isBefore(startOfDay)
          ? startOfDay
          : rec.startTime;
      var effectiveEnd = rec.endTime.isAfter(endOfDay) ? endOfDay : rec.endTime;

      if (effectiveEnd.isBefore(effectiveStart)) continue;

      final startSec = effectiveStart.difference(startOfDay).inSeconds;
      final endSec = effectiveEnd.difference(startOfDay).inSeconds;

      final x1 = (startSec / (24 * 3600)) * size.width;
      final x2 = (endSec / (24 * 3600)) * size.width;

      // Ensure at least 1px width for visibility of short clips
      final width = (x2 - x1).clamp(1.0, size.width);

      canvas.drawRect(
        Rect.fromLTWH(x1, 20, width, size.height - 20),
        segmentPaint,
      );
    }

    // 4. Draw Cursor (Current Time)
    final cursorPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;

    final currentSec = currentTime.difference(startOfDay).inSeconds;
    final cursorX = (currentSec / (24 * 3600)) * size.width;

    // Clamp cursor to view
    if (cursorX >= 0 && cursorX <= size.width) {
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        cursorPaint,
      );

      // Draw Time Label at Cursor
      final timeStr =
          "${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}:${currentTime.second.toString().padLeft(2, '0')}";
      textPainter.text = TextSpan(
        text: timeStr,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      // Ensure label stays onscreen
      double labelX = cursorX - textPainter.width / 2;
      if (labelX < 0) labelX = 0;
      if (labelX + textPainter.width > size.width)
        labelX = size.width - textPainter.width;

      // Draw background box for text clarity
      final bgRect = Rect.fromLTWH(
        labelX - 2,
        size.height / 2 - 2,
        textPainter.width + 4,
        textPainter.height + 4,
      );
      canvas.drawRect(bgRect, Paint()..color = Colors.black87);

      textPainter.paint(canvas, Offset(labelX, size.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.currentTime != currentTime ||
        oldDelegate.recordings != recordings;
  }
}
