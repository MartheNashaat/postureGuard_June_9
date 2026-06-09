import 'package:shared_preferences/shared_preferences.dart';
import '../models/calibration_data.dart';
import '../services/detection_service.dart';
import 'dart:math'; 



class CalibrationService {
  static const _prefix = 'calibration_';

  final List<NormalizedLandmarks> _samples = [];

  void addSample(NormalizedLandmarks landmarks) {
    _samples.add(landmarks);
  }

  int get sampleCount => _samples.length;

  void reset() {
    _samples.clear();
  }

  /// Compute calibration baseline by averaging all collected samples.
  /// Returns null if no samples were collected.
// lib/services/calibration_service.dart (UPDATED computeBaseline)
CalibrationData? computeBaseline({
  double accelX = 0.0,
  double accelY = 0.0,
  double accelZ = -9.8,
}) {
  if (_samples.isEmpty) return null;

  final n = _samples.length.toDouble();

  double sumNoseX = 0, sumNoseY = 0;
  double sumLeftEarX = 0, sumLeftEarY = 0;
  double sumRightEarX = 0, sumRightEarY = 0;
  double sumLeftShoulderX = 0, sumLeftShoulderY = 0;
  double sumRightShoulderX = 0, sumRightShoulderY = 0;

  for (final s in _samples) {
    sumNoseX += s.noseX;
    sumNoseY += s.noseY;
    sumLeftEarX += s.leftEarX;
    sumLeftEarY += s.leftEarY;
    sumRightEarX += s.rightEarX;
    sumRightEarY += s.rightEarY;
    sumLeftShoulderX += s.leftShoulderX;
    sumLeftShoulderY += s.leftShoulderY;
    sumRightShoulderX += s.rightShoulderX;
    sumRightShoulderY += s.rightShoulderY;
  }

  final avgLeftShoulderX = sumLeftShoulderX / n;
  final avgRightShoulderX = sumRightShoulderX / n;
  final avgShoulderWidth = (avgRightShoulderX - avgLeftShoulderX).abs();

  // Calculate variance for more accurate thresholds
  double varianceShoulderY = 0;
  double varianceEarY = 0;
  
  for (final s in _samples) {
    varianceShoulderY += pow((s.leftShoulderY - s.rightShoulderY) - 
        ((sumLeftShoulderY - sumRightShoulderY) / n), 2).toDouble();
    varianceEarY += pow((s.leftEarY - s.rightEarY) - 
        ((sumLeftEarY - sumRightEarY) / n), 2).toDouble();
  }
  
  final stdDevShoulder = sqrt(varianceShoulderY / n);
  final stdDevEar = sqrt(varianceEarY / n);

  return CalibrationData(
    noseX: sumNoseX / n,
    noseY: sumNoseY / n,
    leftEarX: sumLeftEarX / n,
    leftEarY: sumLeftEarY / n,
    rightEarX: sumRightEarX / n,
    rightEarY: sumRightEarY / n,
    leftShoulderX: avgLeftShoulderX,
    leftShoulderY: sumLeftShoulderY / n,
    rightShoulderX: avgRightShoulderX,
    rightShoulderY: sumRightShoulderY / n,
    shoulderWidth: avgShoulderWidth,
    // Dynamic thresholds based on user's natural variance
    shoulderSymmetryThreshold: (stdDevShoulder * 2) + 0.03,
    headTiltThreshold: (stdDevEar * 2) + 0.03,
    shoulderWidthThreshold: avgShoulderWidth * 0.65,
    headDropThreshold: 0.08,
    accelX: accelX,
    accelY: accelY,
    accelZ: accelZ,
  );
}
  /// Save calibration data to shared_preferences.
  Future<void> save(CalibrationData data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.toMap().entries) {
      await prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }

  /// Load calibration data from shared_preferences.
  /// Returns null if no calibration has been saved.
  static Future<CalibrationData?> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if calibration exists
    if (!prefs.containsKey('${_prefix}noseX')) return null;

    final map = <String, double>{};
    for (final key in [
      'noseX', 'noseY',
      'leftEarY', 'rightEarY',
      'leftShoulderX', 'leftShoulderY',
      'rightShoulderX', 'rightShoulderY',
      'shoulderWidth',
      'shoulderSymmetryThreshold', 'headTiltThreshold',
      'shoulderWidthThreshold', 'headDropThreshold',
    ]) {
      final value = prefs.getDouble('$_prefix$key');
      if (value == null) return null;
      map[key] = value;
    }
    // Ear X coords added later — load if present, fromMap handles the fallback
    for (final key in ['leftEarX', 'rightEarX']) {
      final value = prefs.getDouble('$_prefix$key');
      if (value != null) map[key] = value;
    }
    // Accel baseline — optional for backward compat with old calibrations
    for (final key in ['accelX', 'accelY', 'accelZ']) {
      final value = prefs.getDouble('$_prefix$key');
      if (value != null) map[key] = value;
    }

    return CalibrationData.fromMap(map);
  }

  /// Clear saved calibration data.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
