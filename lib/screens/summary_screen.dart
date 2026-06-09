import 'package:flutter/material.dart';
import '../models/session_summary.dart';
import '../services/database_service.dart';
import '../widgets/heatmap_chart.dart';

class SummaryScreen extends StatefulWidget {
  final SessionSummary summary;

  const SummaryScreen({super.key, required this.summary});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  List<int>? _statusPerSecond;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final events =
        await DatabaseService.getSessionEvents(widget.summary.sessionId);
    if (mounted) {
      setState(() {
        _statusPerSecond =
            events.map((e) => e['status'] as int).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final scoreColor = s.goodPosturePercent >= 80
        ? Colors.green
        : s.goodPosturePercent >= 50
            ? Colors.orange
            : Colors.red;

    // PiP mode: tiny window — show only the session score
    if (MediaQuery.of(context).size.width < 300) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${s.goodPosturePercent.round()}%',
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Session',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Score circle
            Center(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor, width: 6),
                  color: scoreColor.withValues(alpha: 0.1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${s.goodPosturePercent.round()}%',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      'Good Posture',
                      style: TextStyle(
                        fontSize: 14,
                        color: scoreColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Stats cards
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: s.formattedDuration,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.local_fire_department,
                    label: 'Best Streak',
                    value: _formatStreak(s.longestStreakSeconds),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (s.worstMomentTimestamp != null)
              _statCard(
                icon: Icons.warning_amber_rounded,
                label: 'Worst Moment',
                value: _formatTime(s.worstMomentTimestamp!),
              ),

            const SizedBox(height: 28),

            // Heatmap chart
            const Text(
              'Posture Timeline',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Good posture % per minute',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: _statusPerSecond == null
                  ? const Center(child: CircularProgressIndicator())
                  : _statusPerSecond!.isEmpty
                      ? const Center(
                          child: Text('No data recorded',
                              style: TextStyle(color: Colors.grey)))
                      : HeatmapChart(statusPerSecond: _statusPerSecond!),
            ),

            const SizedBox(height: 32),

            // Back to home button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Back to Home',
                    style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: Colors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatStreak(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}m ${secs}s';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
