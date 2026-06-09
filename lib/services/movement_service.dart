// lib/services/movement_service.dart
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';

class MovementService {
  static final MovementService _instance = MovementService._internal();
  factory MovementService() => _instance;
  MovementService._internal();

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  
  // THESE WERE MISSING - declare the variables
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _currentZ = 0.0;
  
  // Calibration values (baseline phone orientation)
  double _calibratedX = 0.0;
  double _calibratedY = 0.0;
  double _calibratedZ = 0.0;
  
  // Thresholds
  static const double tiltThreshold = 0.3;
  static const double movementThreshold = 0.5;
  static const double shakeThreshold = 2.0;
  
  // Callback for movement alerts
  Function(String alert)? onMovementAlert;
  
  // Getters
  bool get hasPhoneTilt {
    final tiltX = (_currentX - _calibratedX).abs();
    final tiltY = (_currentY - _calibratedY).abs();
    return tiltX > tiltThreshold || tiltY > tiltThreshold;
  }
  
  bool get hasSignificantMovement {
    final moveX = (_currentX - _calibratedX).abs();
    final moveY = (_currentY - _calibratedY).abs();
    final moveZ = (_currentZ - _calibratedZ).abs();
    return moveX > movementThreshold || moveY > movementThreshold || moveZ > movementThreshold;
  }
  
  bool get isShaking {
    final shakeX = _currentX.abs();
    final shakeY = _currentY.abs();
    final shakeZ = _currentZ.abs();
    return shakeX > shakeThreshold || shakeY > shakeThreshold || shakeZ > shakeThreshold;
  }
  
  double get phoneTiltAngle {
    final tiltX = (_currentX - _calibratedX).abs();
    final tiltY = (_currentY - _calibratedY).abs();
    final angleDegrees = (tiltX + tiltY) * 30;
    return angleDegrees.clamp(0.0, 45.0);
  }
  
  String get movementStatus {
    if (isShaking) return "Phone is shaking!";
    if (hasPhoneTilt) return "Phone tilted ${phoneTiltAngle.round()}°";
    if (hasSignificantMovement) return "Phone moved significantly";
    return "Phone stable";
  }
  
  void startListening() {
    _subscription = userAccelerometerEvents.listen((event) {
      _currentX = event.x;
      _currentY = event.y;
      _currentZ = event.z;
      
      // Check for movement alerts
      _checkForAlerts();
    });
  }
  
  void calibrate() {
    // Capture current phone orientation as baseline
    _calibratedX = _currentX;
    _calibratedY = _currentY;
    _calibratedZ = _currentZ;
    debugPrint('MovementService calibrated: X=$_calibratedX, Y=$_calibratedY, Z=$_calibratedZ');
  }
  
  void _checkForAlerts() {
    if (isShaking) {
      onMovementAlert?.call("Please hold your phone steady");
    } else if (hasPhoneTilt && phoneTiltAngle > 20) {
      onMovementAlert?.call("Phone tilted too much");
    }
  }
  
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
  
  void reset() {
    _currentX = 0.0;
    _currentY = 0.0;
    _currentZ = 0.0;
    _calibratedX = 0.0;
    _calibratedY = 0.0;
    _calibratedZ = 0.0;
  }
  
  void dispose() {
    stopListening();
  }
}