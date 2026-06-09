// lib/widgets/baseline_overlay.dart
import 'package:flutter/material.dart';
import '../services/detection_service.dart';
import 'skeleton_overlay.dart';

class BaselineOverlay extends StatelessWidget {
  final NormalizedLandmarks? baseline;
  final bool showInstructions;

  const BaselineOverlay({
    super.key,
    required this.baseline,
    this.showInstructions = false,
  });

  @override
  Widget build(BuildContext context) {
    if (baseline == null) return const SizedBox.shrink();

    return Stack(
      children: [
        // Semi-transparent ghost skeleton
        CustomPaint(
          size: Size.infinite,
          painter: SkeletonPainter(
            landmarks: baseline!,
            color: Colors.teal.withOpacity(0.25), // Ghost effect
            mirrored: true,
          ),
        ),
        // Instruction overlay if needed
        if (showInstructions)
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fit_screen, color: Colors.teal, size: 24),
                  SizedBox(height: 8),
                  Text(
                    'Match your posture to the ghost outline',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The teal outline shows your ideal posture',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}