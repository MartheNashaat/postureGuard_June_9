import 'dart:ui'; // Required for Offset
import '../services/detection_service.dart';
class CalibrationData {
  final double noseX;
  final double noseY;
  final double leftEarX;
  final double leftEarY;
  final double rightEarX;
  final double rightEarY;
  final double leftShoulderX;
  final double leftShoulderY;
  final double rightShoulderX;
  final double rightShoulderY;
  final double shoulderWidth;

  // Thresholds derived from calibration
  final double shoulderSymmetryThreshold;
  final double headTiltThreshold;
  final double shoulderWidthThreshold;
  final double headDropThreshold;

  // Accelerometer baseline — gravity vector recorded during calibration
  final double accelX;
  final double accelY;
  final double accelZ;

  const CalibrationData({
    required this.noseX,
    required this.noseY,
    required this.leftEarX,
    required this.leftEarY,
    required this.rightEarX,
    required this.rightEarY,
    required this.leftShoulderX,
    required this.leftShoulderY,
    required this.rightShoulderX,
    required this.rightShoulderY,
    required this.shoulderWidth,
    this.shoulderSymmetryThreshold = 0.05,
    this.headTiltThreshold = 0.04,
    this.shoulderWidthThreshold = 0.25,
    this.headDropThreshold = 0.07,
    this.accelX = 0.0,
    this.accelY = 0.0,
    this.accelZ = -9.8,
  });

  Map<String, double> toMap() => {
        'noseX': noseX,
        'noseY': noseY,
        'leftEarX': leftEarX,
        'leftEarY': leftEarY,
        'rightEarX': rightEarX,
        'rightEarY': rightEarY,
        'leftShoulderX': leftShoulderX,
        'leftShoulderY': leftShoulderY,
        'rightShoulderX': rightShoulderX,
        'rightShoulderY': rightShoulderY,
        'shoulderWidth': shoulderWidth,
        'shoulderSymmetryThreshold': shoulderSymmetryThreshold,
        'headTiltThreshold': headTiltThreshold,
        'shoulderWidthThreshold': shoulderWidthThreshold,
        'headDropThreshold': headDropThreshold,
        'accelX': accelX,
        'accelY': accelY,
        'accelZ': accelZ,
      };

  factory CalibrationData.fromMap(Map<String, double> map) => CalibrationData(
        noseX: map['noseX']!,
        noseY: map['noseY']!,
        leftEarX: map['leftEarX'] ?? map['noseX']!,
        leftEarY: map['leftEarY']!,
        rightEarX: map['rightEarX'] ?? map['noseX']!,
        rightEarY: map['rightEarY']!,
        leftShoulderX: map['leftShoulderX']!,
        leftShoulderY: map['leftShoulderY']!,
        rightShoulderX: map['rightShoulderX']!,
        rightShoulderY: map['rightShoulderY']!,
        shoulderWidth: map['shoulderWidth']!,
        shoulderSymmetryThreshold:
            map['shoulderSymmetryThreshold'] ?? 0.05,
        headTiltThreshold: map['headTiltThreshold'] ?? 0.04,
        shoulderWidthThreshold: map['shoulderWidthThreshold'] ?? 0.25,
        headDropThreshold: map['headDropThreshold'] ?? 0.07,
        accelX: map['accelX'] ?? 0.0,
        accelY: map['accelY'] ?? 0.0,
        accelZ: map['accelZ'] ?? -9.8,
      );

      NormalizedLandmarks get asLandmarks => NormalizedLandmarks(
        noseX: noseX,
        noseY: noseY,
        leftEarX: leftEarX,
        leftEarY: leftEarY,
        rightEarX: rightEarX,
        rightEarY: rightEarY,
        leftShoulderX: leftShoulderX,
        leftShoulderY: leftShoulderY,
        rightShoulderX: rightShoulderX,
        rightShoulderY: rightShoulderY,
      );
}
