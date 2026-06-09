// lib/services/posture_analyzer.dart (UPDATED)
import 'dart:math';
import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/detection_service.dart';

class PostureAnalysisResult {
  final PostureStatus status;
  final bool shoulderAsymmetry;
  final bool headTilt;
  final bool shoulderRounding;
  final bool headDrop;
  final bool headRaise;
  final double shoulderSymmetryPercent;
  final double headTiltPercent;
  final double shoulderRoundingPercent;
  final double headDropPercent;
  final double headRaisePercent;

  const PostureAnalysisResult({
    required this.status,
    required this.shoulderAsymmetry,
    required this.headTilt,
    required this.shoulderRounding,
    required this.headDrop,
    required this.headRaise,
    this.shoulderSymmetryPercent = 100,
    this.headTiltPercent = 100,
    this.shoulderRoundingPercent = 100,
    this.headDropPercent = 100,
    this.headRaisePercent = 100,
  });

  int get violationCount =>
      (shoulderAsymmetry ? 1 : 0) +
      (headTilt ? 1 : 0) +
      (shoulderRounding ? 1 : 0) +
      (headDrop ? 1 : 0) +
      (headRaise ? 1 : 0);

  double get overallScore {
    final scores = [shoulderSymmetryPercent, headTiltPercent, shoulderRoundingPercent, headDropPercent, headRaisePercent];
    return (scores.reduce((a, b) => a + b) / scores.length).clamp(0.0, 100.0);
  }

  List<String> get violationMessages {
    final messages = <String>[];
    // Phone position violations take full priority — suppress all other labels.
    // headDrop = nose low in image = phone too high above head.
    // headRaise = nose high in image = phone too low.
    if (headDrop) {
      messages.add('Phone too high');
      return messages;
    }
    if (headRaise) {
      messages.add('Phone too low');
      return messages;
    }
    if (shoulderAsymmetry) messages.add('Shoulders uneven');
    if (headTilt) messages.add('Head tilting');
    if (shoulderRounding) messages.add('Shoulders rounding');
    return messages;
  }

  static const good = PostureAnalysisResult(
    status: PostureStatus.good,
    shoulderAsymmetry: false,
    headTilt: false,
    shoulderRounding: false,
    headDrop: false,
    headRaise: false,
  );
}

class PostureAnalyzer {
  final CalibrationData calibration;

  // EMA smoothing on the NTS value — lower α means more noise filtering but
  // slightly slower response. 0.15 prevents single noisy frames from crossing
  // the threshold and flickering between phone-too-low and other states.
  static const double _ntsAlpha = 0.15;
  double _smoothNTS = double.nan;

  // Camera-NTS hysteresis: once a violation fires via camera, keep it active
  // until NTS returns well past the threshold.
  bool _headRaiseActive = false;
  bool _headDropActive = false;

  // Accel-pitch hysteresis: same pattern but driven by gravity vector.
  bool _accelTooLowActive  = false;
  bool _accelTooHighActive = false;

  PostureAnalyzer(this.calibration);

  // Returns the signed pitch angle in radians between the baseline and current
  // gravity vectors.
  // Positive → phone top tilted away from the user (camera looks up → too LOW).
  // Negative → phone top tilted toward the user (camera looks down → too HIGH).
  // The X component of (b × c) encodes the rotation axis direction, but its
  // sign corresponds to phone-too-HIGH (crossX > 0 = top toward user), so we
  // negate it to get the intuitive positive = too-low convention.
  double _signedPitch(
    double bx, double by, double bz,
    double cx, double cy, double cz,
  ) {
    final bLen = sqrt(bx * bx + by * by + bz * bz);
    final cLen = sqrt(cx * cx + cy * cy + cz * cz);
    if (bLen < 0.1 || cLen < 0.1) return 0.0;
    final dot = (bx * cx + by * cy + bz * cz) / (bLen * cLen);
    final angle = acos(dot.clamp(-1.0, 1.0));
    final crossX = by * cz - bz * cy; // X component of b × c
    // crossX > 0 → top toward user → too HIGH → return negative angle
    // crossX < 0 → top away from user → too LOW  → return positive angle
    return crossX >= 0 ? -angle : angle;
  }

  // Pass the EMA-smoothed accelerometer values from session_screen so the
  // gravity-based pitch can confirm or independently trigger phone-too-low /
  // phone-too-high even when the camera NTS is noisy or shoulders are off frame.
  PostureAnalysisResult analyze(
    NormalizedLandmarks landmarks, {
    double? accelX,
    double? accelY,
    double? accelZ,
  }) {
    // ── Shoulder width (scale reference) ─────────────────────────────────────
    final currentShoulderWidth = (landmarks.leftShoulderX - landmarks.rightShoulderX).abs();
    final safeWidth         = currentShoulderWidth.clamp(0.01, 1.0);
    final safeBaselineWidth = calibration.shoulderWidth.clamp(0.01, 1.0);

    // ── Phone position via Nose-To-Shoulder ratio (NTS) ──────────────────────
    // NTS = (shoulderMidY – noseY) / shoulderWidth.  Larger → nose further
    // above shoulders.  Scale-invariant and position-independent.
    final currentShoulderMidY  = (landmarks.leftShoulderY  + landmarks.rightShoulderY)  / 2;
    final baselineShoulderMidY = (calibration.leftShoulderY + calibration.rightShoulderY) / 2;
    final rawNTS      = (currentShoulderMidY  - landmarks.noseY)  / safeWidth;
    final baselineNTS = (baselineShoulderMidY - calibration.noseY) / safeBaselineWidth;

    // Smooth NTS across frames (EMA) so a single noisy frame cannot flip
    // the direction from "phone too low" to "phone too high" or vice versa.
    if (_smoothNTS.isNaN) {
      _smoothNTS = rawNTS;
    } else {
      _smoothNTS = _ntsAlpha * rawNTS + (1 - _ntsAlpha) * _smoothNTS;
    }

    // Hard threshold: requires the phone to move well above/below the head.
    final ratioThreshold = calibration.headDropThreshold / safeBaselineWidth;
    // Soft threshold: suppress body checks before the hard violation fires.
    final ratioSoft = ratioThreshold * 0.5;

    // Phone too HIGH: NTS decreased → nose lower in image vs baseline
    final ntsDrop = (baselineNTS - _smoothNTS).clamp(0.0, double.infinity);
    final cameraHeadDropPercent = (1.0 - ntsDrop / ratioThreshold).clamp(0.0, 1.0) * 100;

    // Phone too LOW: NTS increased → nose higher in image vs baseline
    final ntsRise = (_smoothNTS - baselineNTS).clamp(0.0, double.infinity);
    final cameraHeadRaisePercent = (1.0 - ntsRise / ratioThreshold).clamp(0.0, 1.0) * 100;

    // Camera NTS hysteresis (65 % exit threshold).
    const hysteresisExit = 0.65;
    if (ntsRise > ratioThreshold) {
      _headRaiseActive = true;
      _headDropActive = false;
    } else if (_headRaiseActive && ntsRise < ratioThreshold * hysteresisExit) {
      _headRaiseActive = false;
    }
    if (ntsDrop > ratioThreshold) {
      _headDropActive = true;
      _headRaiseActive = false;
    } else if (_headDropActive && ntsDrop < ratioThreshold * hysteresisExit) {
      _headDropActive = false;
    }

    // ── Gravity-based phone direction ─────────────────────────────────────────
    // The signed pitch between calibration and current gravity vectors tells us
    // if the phone is tilted toward "too low" (positive) or "too high" (negative)
    // independently of the camera.  Threshold: 15° from calibration position.
    const accelThreshRad = 15.0 * pi / 180;
    double accelHeadRaisePercent = 100.0;
    double accelHeadDropPercent  = 100.0;

    if (accelX != null && accelY != null && accelZ != null) {
      final pitch = _signedPitch(
        calibration.accelX, calibration.accelY, calibration.accelZ,
        accelX, accelY, accelZ,
      );
      // Score: 100 % at 0 °, 0 % at threshold.
      accelHeadRaisePercent = (1.0 - pitch.clamp(0.0, double.infinity) / accelThreshRad).clamp(0.0, 1.0) * 100;
      accelHeadDropPercent  = (1.0 - (-pitch).clamp(0.0, double.infinity) / accelThreshRad).clamp(0.0, 1.0) * 100;

      final pitchDeg = pitch * 180 / pi;
      if (pitchDeg > 15.0) {
        _accelTooLowActive  = true;
        _accelTooHighActive = false;
      } else if (_accelTooLowActive && pitchDeg < 15.0 * hysteresisExit) {
        _accelTooLowActive = false;
      }
      if (pitchDeg < -15.0) {
        _accelTooHighActive = true;
        _accelTooLowActive  = false;
      } else if (_accelTooHighActive && pitchDeg > -15.0 * hysteresisExit) {
        _accelTooHighActive = false;
      }
    }

    // Combine camera NTS and accelerometer, keeping them mutually exclusive.
    // Accel takes priority when it has a clear directional signal — it is
    // immune to NTS noise from shoulders leaving the frame.  When the accel
    // is silent (neither active), fall back to the camera NTS state.
    final bool headRaise;
    final bool headDrop;
    if (_accelTooLowActive) {
      headRaise = true;
      headDrop  = false;
    } else if (_accelTooHighActive) {
      headDrop  = true;
      headRaise = false;
    } else {
      headRaise = _headRaiseActive;
      headDrop  = _headDropActive;
    }

    // Use the worse of the two signals for scoring so either sensor contributes
    // to the score penalty.
    final headRaisePercent = min(cameraHeadRaisePercent, accelHeadRaisePercent);
    final headDropPercent  = min(cameraHeadDropPercent,  accelHeadDropPercent);

    // Suppress all body checks once the phone starts moving toward an extreme
    // position (soft zone), not just after the hard threshold is crossed.
    // This eliminates false shoulder-rounding caused by perspective distortion.
    // Also suppress when either shoulder is near the frame edge — partial
    // visibility makes width/height readings unreliable.
    // Top edge uses 0.15 (not 0.05) because when the phone is low, ML Kit
    // estimates shoulders at ~0.08–0.14 even when physically off-screen.
    final shouldersOffScreen =
        landmarks.leftShoulderY  > 0.88 || landmarks.rightShoulderY  > 0.88 ||
        landmarks.leftShoulderY  < 0.15 || landmarks.rightShoulderY  < 0.15;

    final extremePhonePosition =
        headDrop || headRaise ||
        ntsDrop > ratioSoft || ntsRise > ratioSoft ||
        shouldersOffScreen;

    // ── Shoulder rounding: width narrowed vs baseline ────────────────────────
    final widthNarrowed = (calibration.shoulderWidth - currentShoulderWidth).clamp(0.0, double.infinity);
    const _roundingTrigger = 0.04;
    const _roundingZero    = 0.08;
    final shoulderRoundingPercent = (1.0 - widthNarrowed / _roundingZero).clamp(0.0, 1.0) * 100;
    final shoulderRounding = !extremePhonePosition && widthNarrowed > _roundingTrigger;

    // ── Shoulder asymmetry: excess height difference vs baseline ─────────────
    // Compare each shoulder to its own calibration baseline, then measure
    // how differently they moved relative to each other.  The old approach
    // (|current| - |baseline|) was directionally biased: the shoulder moving
    // in the same direction as the natural calibration tilt would trigger much
    // sooner than the opposite shoulder. This formula is fully symmetric.
    final leftDelta  = landmarks.leftShoulderY  - calibration.leftShoulderY;
    final rightDelta = landmarks.rightShoulderY - calibration.rightShoulderY;
    final shoulderAsymmetryExcess = (leftDelta - rightDelta).abs();
    const _shoulderYTrigger = 0.04;
    const _shoulderYZero    = 0.07;
    final shoulderSymmetryPercent = (1.0 - shoulderAsymmetryExcess / _shoulderYZero).clamp(0.0, 1.0) * 100;
    final shoulderAsymmetry = !extremePhonePosition && shoulderAsymmetryExcess > _shoulderYTrigger;

    // ── Head tilt: excess ear-Y difference vs baseline ───────────────────────
    final baselineEarDiff = (calibration.leftEarY  - calibration.rightEarY).abs();
    final currentEarDiff  = (landmarks.leftEarY    - landmarks.rightEarY).abs();
    final headTiltExcess  = (currentEarDiff - baselineEarDiff).clamp(0.0, double.infinity);
    final headTiltPercent = (1.0 - headTiltExcess / calibration.headTiltThreshold).clamp(0.0, 1.0) * 100;
    final headTilt = !extremePhonePosition && headTiltExcess > calibration.headTiltThreshold;

    final violations = (shoulderAsymmetry ? 1 : 0) +
        (headTilt ? 1 : 0) +
        (shoulderRounding ? 1 : 0) +
        (headDrop ? 1 : 0) +
        (headRaise ? 1 : 0);

    return PostureAnalysisResult(
      status: PostureStatus.fromViolationCount(violations),
      shoulderAsymmetry: shoulderAsymmetry,
      headTilt: headTilt,
      shoulderRounding: shoulderRounding,
      headDrop: headDrop,
      headRaise: headRaise,
      shoulderSymmetryPercent: shoulderSymmetryPercent,
      headTiltPercent: headTiltPercent,
      shoulderRoundingPercent: shoulderRoundingPercent,
      headDropPercent: headDropPercent,
      headRaisePercent: headRaisePercent,
    );
  }

}