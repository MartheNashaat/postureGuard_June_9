// lib/services/feedback_service.dart (UPDATED)
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../models/posture_status.dart';
import '../services/posture_analyzer.dart';

class FeedbackService {
  final FlutterTts _tts = FlutterTts();

  static const int _badPostureThresholdSeconds = 5;
  static const int _alertCooldownSeconds = 5;
  int _consecutiveBadSeconds = 0;
  DateTime? _lastAlertTime;

  static const int _scoreWindowSize = 30;
  final Queue<double> _scoreWindow = Queue<double>(); // Now stores actual scores

  int _goodStreakSeconds = 0;
  DateTime? _lastStreakUpdateTime;

  DateTime? _lastSecondCheck;
  double _totalScoreThisSecond = 0.0;
  int _framesThisSecond = 0;

  double get scorePercent {
    if (_scoreWindow.isEmpty) return 1.0;
    double sum = 0;
    for (final score in _scoreWindow) {
      sum += score;
    }
    return sum / _scoreWindow.length / 100.0;
  }

  int get goodStreakMinutes => _goodStreakSeconds ~/ 60;
  int get goodStreakSeconds => _goodStreakSeconds;

  Future<void> initialize() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void onFrame(PostureAnalysisResult result) {
    final currentScore = result.overallScore;
    
    // Update score window with actual percentage
    _scoreWindow.addLast(currentScore);
    if (_scoreWindow.length > _scoreWindowSize) {
      _scoreWindow.removeFirst();
    }

    // Update streak based on good posture (score >= 80)
    final isGood = currentScore >= 80;
    _updateStreak(isGood);

    // Track for alerts - using score severity
    _trackPostureSeverity(result);
  }

  void _updateStreak(bool isGood) {
    if (isGood) {
      final now = DateTime.now();
      if (_lastStreakUpdateTime == null ||
          now.difference(_lastStreakUpdateTime!).inMilliseconds >= 1000) {
        _lastStreakUpdateTime = now;
        _goodStreakSeconds++;
      }
    } else {
      _goodStreakSeconds = 0;
      _lastStreakUpdateTime = null;
    }
  }

  void _trackPostureSeverity(PostureAnalysisResult result) {
    final now = DateTime.now();

    if (_lastSecondCheck == null ||
        now.difference(_lastSecondCheck!).inMilliseconds >= 1000) {
      if (_lastSecondCheck != null && _framesThisSecond > 0) {
        final avgScore = _totalScoreThisSecond / _framesThisSecond;
        final isBadSecond = avgScore < 50; // Below 50% is bad
        
        if (isBadSecond) {
          _consecutiveBadSeconds++;
        } else {
          _consecutiveBadSeconds = 0;
        }

        if (_consecutiveBadSeconds >= _badPostureThresholdSeconds) {
          _tryFireAlert(result);
        }
      }

      _lastSecondCheck = now;
      _totalScoreThisSecond = 0;
      _framesThisSecond = 0;
    }

    _totalScoreThisSecond += result.overallScore;
    _framesThisSecond++;
  }

  void _tryFireAlert(PostureAnalysisResult result) {
    final now = DateTime.now();

    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!).inSeconds < _alertCooldownSeconds) {
      return;
    }

    _lastAlertTime = now;
    // Do NOT reset _consecutiveBadSeconds — keep it accumulating so the
    // 5-second cooldown is the only gate and the sound repeats every 5s.

    final messages = result.violationMessages;
    if (messages.isNotEmpty) {
      _speak(messages.first);
    }

    _vibrate();
  }

  Future<void> _speak(String message) async {
    try {
      await _tts.speak(message);
    } catch (e) {
      debugPrint('FeedbackService: TTS error: $e');
    }
  }

  Future<void> _vibrate() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(duration: 200);
      }
    } catch (e) {
      debugPrint('FeedbackService: Vibration error: $e');
    }
  }

  void reset() {
    _scoreWindow.clear();
    _consecutiveBadSeconds = 0;
    _lastAlertTime = null;
    _goodStreakSeconds = 0;
    _lastStreakUpdateTime = null;
    _lastSecondCheck = null;
    _totalScoreThisSecond = 0;
    _framesThisSecond = 0;
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}