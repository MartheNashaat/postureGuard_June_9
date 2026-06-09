import 'package:flutter/material.dart';
import '../models/posture_status.dart';
import '../services/detection_service.dart';

class SkeletonOverlay extends StatelessWidget {
  final NormalizedLandmarks landmarks;
  final PostureStatus status;
  final bool mirrored;

  const SkeletonOverlay({
    super.key,
    required this.landmarks,
    this.status = PostureStatus.good,
    this.mirrored = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SkeletonPainter(
        landmarks: landmarks,
        color: status.color,
        mirrored: mirrored,
      ),
      size: Size.infinite,
    );
  }
}

class SkeletonPainter extends CustomPainter {
  final NormalizedLandmarks landmarks;
  final Color color;
  final bool mirrored;

  SkeletonPainter({
    required this.landmarks,
    required this.color,
    required this.mirrored,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Convert normalized coords to canvas pixels
    // final nose = _toCanvas(landmarks.noseX, landmarks.noseY, size);
    // final leftEar = _toCanvas(landmarks.leftEarX, landmarks.leftEarY, size);
    // final rightEar = _toCanvas(landmarks.rightEarX, landmarks.rightEarY, size);
    // final leftShoulder =
    //     _toCanvas(landmarks.leftShoulderX, landmarks.leftShoulderY, size);
    // final rightShoulder =
    //     _toCanvas(landmarks.rightShoulderX, landmarks.rightShoulderY, size);
// Inside SkeletonPainter.paint
    // Instead of landmarks.noseX, use landmarks.nose.dx
    final nose = _toCanvas(landmarks.noseX, landmarks.noseY, size);
    final leftEar = _toCanvas(landmarks.leftEarX, landmarks.leftEarY, size);
    final rightEar = _toCanvas(landmarks.rightEarX, landmarks.rightEarY, size);
    final leftShoulder = _toCanvas(landmarks.leftShoulderX, landmarks.leftShoulderY, size);
    final rightShoulder = _toCanvas(landmarks.rightShoulderX, landmarks.rightShoulderY, size);    // Draw connections
    // Ears to nose
    canvas.drawLine(leftEar, nose, linePaint);
    canvas.drawLine(rightEar, nose, linePaint);
    // Shoulders line
    canvas.drawLine(leftShoulder, rightShoulder, linePaint);
    // Nose to shoulder midpoint (spine line)
    final shoulderMid = Offset(
      (leftShoulder.dx + rightShoulder.dx) / 2,
      (leftShoulder.dy + rightShoulder.dy) / 2,
    );
    canvas.drawLine(nose, shoulderMid, linePaint);

    // Draw glow circles behind dots
    const glowRadius = 16.0;
    const dotRadius = 8.0;

    for (final point in [nose, leftEar, rightEar, leftShoulder, rightShoulder]) {
      canvas.drawCircle(point, glowRadius, glowPaint);
      canvas.drawCircle(point, dotRadius, dotPaint);
    }

    // Draw labels
    _drawLabel(canvas, nose, 'Nose', size);
    _drawLabel(canvas, leftShoulder, 'L', size);
    _drawLabel(canvas, rightShoulder, 'R', size);
  }

  Offset _toCanvas(double nx, double ny, Size size) {
    // Front camera is mirrored: flip X
    final x = mirrored ? (1.0 - nx) * size.width : nx * size.width;
    final y = ny * size.height;
    return Offset(x, y);
  }

  void _drawLabel(Canvas canvas, Offset point, String text, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (point.dx - textPainter.width / 2).clamp(0, size.width - textPainter.width),
      point.dy - 22,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(SkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.color != color;
  }
}
