import 'package:flutter/material.dart';

class ScoreMeter extends StatelessWidget {
  final double score; // 0.0 to 1.0
  final double height;

  const ScoreMeter({
    super.key,
    required this.score,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final clampedScore = score.clamp(0.0, 1.0);
    final color = Color.lerp(Colors.red, Colors.green, clampedScore)!;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Posture Score',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${(clampedScore * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: LinearProgressIndicator(
                  value: clampedScore,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: height,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
