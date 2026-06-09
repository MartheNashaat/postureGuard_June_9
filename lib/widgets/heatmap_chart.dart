import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Per-minute posture heatmap: each bar represents one minute,
/// colored green (good), yellow (warning), or red (bad) based on
/// the dominant status during that minute.
class HeatmapChart extends StatelessWidget {
  /// List of per-second status values (0=good, 1=warning, 2=bad).
  final List<int> statusPerSecond;

  const HeatmapChart({super.key, required this.statusPerSecond});

  @override
  Widget build(BuildContext context) {
    final minuteData = _aggregateByMinute();
    if (minuteData.isEmpty) {
      return const Center(
        child: Text('No data to display',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                'Min ${group.x + 1}\n${rod.toY.round()}% good',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                // Show every label if <= 10 minutes, else every 2nd
                if (minuteData.length > 10 && idx % 2 != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${idx + 1}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
              reservedSize: 20,
            ),
            axisNameWidget: const Text('Minute',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 25,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _buildBarGroups(minuteData),
      ),
    );
  }

  /// Returns list of (goodPercent) per minute.
  List<double> _aggregateByMinute() {
    if (statusPerSecond.isEmpty) return [];

    final minutes = <double>[];
    for (int i = 0; i < statusPerSecond.length; i += 60) {
      final chunk = statusPerSecond.sublist(
        i,
        (i + 60).clamp(0, statusPerSecond.length),
      );
      final goodCount = chunk.where((s) => s == 0).length;
      minutes.add((goodCount / chunk.length) * 100);
    }
    return minutes;
  }

  List<BarChartGroupData> _buildBarGroups(List<double> minuteData) {
    return List.generate(minuteData.length, (i) {
      final goodPercent = minuteData[i];
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: goodPercent,
            width: minuteData.length > 15 ? 8 : 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            color: _barColor(goodPercent),
          ),
        ],
      );
    });
  }

  Color _barColor(double goodPercent) {
    if (goodPercent >= 80) return Colors.green;
    if (goodPercent >= 50) return Colors.orange;
    return Colors.red;
  }
}
