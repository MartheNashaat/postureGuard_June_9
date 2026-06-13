// lib/services/posture_analyzer.dart
import 'dart:math';
import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/detection_service.dart';

class PostureAnalysisResult {
  final PostureStatus status;
  final bool shoulderAsymmetry;
  final bool headTilt;
  final bool shoulderRounding;
  final bool headRise;       // camera: nose rose above baseline (head moved up)
  final bool headDrop;       // camera: nose dropped below baseline (head moved down)
  final bool phoneTooLow;    // accel: phone physically tilted too far back
  final bool phoneTooHigh;   // accel: phone physically tilted too far forward
  final double shoulderSymmetryPercent;
  final double headTiltPercent;
  final double shoulderRoundingPercent;
  final double headRisePercent;
  final double headDropPercent;
  final double phoneTooLowPercent;
  final double phoneTooHighPercent;

  const PostureAnalysisResult({
    required this.status,
    required this.shoulderAsymmetry,
    required this.headTilt,
    required this.shoulderRounding,
    required this.headRise,
    required this.headDrop,
    required this.phoneTooLow,
    required this.phoneTooHigh,
    this.shoulderSymmetryPercent = 100,
    this.headTiltPercent = 100,
    this.shoulderRoundingPercent = 100,
    this.headRisePercent = 100,
    this.headDropPercent = 100,
    this.phoneTooLowPercent = 100,
    this.phoneTooHighPercent = 100,
  });

  int get violationCount =>
      (shoulderAsymmetry ? 1 : 0) +
      (headTilt ? 1 : 0) +
      (shoulderRounding ? 1 : 0) +
      (headRise ? 1 : 0) +
      (headDrop ? 1 : 0) +
      (phoneTooLow ? 1 : 0) +
      (phoneTooHigh ? 1 : 0);

  double get overallScore {
    final scores = [
      shoulderSymmetryPercent,
      headTiltPercent,
      shoulderRoundingPercent,
      headRisePercent,
      headDropPercent,
      phoneTooLowPercent,
      phoneTooHighPercent,
    ];
    return (scores.reduce((a, b) => a + b) / scores.length).clamp(0.0, 100.0);
  }

  List<String> get violationMessages {
    // Accel-based phone position has highest priority.
    if (phoneTooHigh) return ['Phone too high'];
    if (phoneTooLow)  return ['Phone too low'];
    // Camera-based head position.
    if (headDrop) return ['Head dropped'];
    if (headRise) return ['Head raised'];
    // Body posture — each fires only for its own cause.
    final messages = <String>[];
    if (shoulderAsymmetry) messages.add('Shoulders uneven');
    if (headTilt)          messages.add('Head tilting');
    if (shoulderRounding)  messages.add('Shoulders rounding');
    return messages;
  }

  static const good = PostureAnalysisResult(
    status: PostureStatus.good,
    shoulderAsymmetry: false,
    headTilt: false,
    shoulderRounding: false,
    headRise: false,
    headDrop: false,
    phoneTooLow: false,
    phoneTooHigh: false,
  );
}

class PostureAnalyzer {
  final CalibrationData calibration;

  // EMA smoothing on camera NTS.
  // 0.25 (up from 0.15): faster response so the NTS soft zone suppresses
  // shoulder checks sooner when the phone starts moving up/down.
  static const double _ntsAlpha = 0.25;
  double _smoothNTS = double.nan;

  // Camera NTS hysteresis — head position relative to shoulders.
  bool _headRaiseActive = false;
  bool _headDropActive  = false;

  // Accel hysteresis — physical phone orientation.
  bool _accelTooLowActive  = false;
  bool _accelTooHighActive = false;

  // Body-check hysteresis — prevents per-frame flickering on all three checks.
  bool _headTiltActive          = false;
  bool _shoulderAsymmetryActive = false;
  bool _shoulderRoundingActive  = false;

  PostureAnalyzer(this.calibration);

  // Returns the signed pitch angle in radians between the baseline and current
  // gravity vectors. Positive → phone tilted too low (top away from user).
  // Negative → phone tilted too high (top toward user).
  double _signedPitch(
    double bx, double by, double bz,
    double cx, double cy, double cz,
  ) {
    final bLen = sqrt(bx * bx + by * by + bz * bz);
    final cLen = sqrt(cx * cx + cy * cy + cz * cz);
    if (bLen < 0.1 || cLen < 0.1) return 0.0;
    final dot = (bx * cx + by * cy + bz * cz) / (bLen * cLen);
    final angle = acos(dot.clamp(-1.0, 1.0));
    final crossX = by * cz - bz * cy;
    // crossX > 0 → top toward user → too HIGH → negative angle
    return crossX >= 0 ? -angle : angle;
  }

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

    // ── Camera NTS: head/nose position relative to shoulders ─────────────────
    // NTS = (shoulderMidY – noseY) / shoulderWidth. Scale-invariant.
    // Increases when nose appears higher (head up / phone lower).
    // Decreases when nose appears lower (head down / phone higher).
    final currentShoulderMidY  = (landmarks.leftShoulderY  + landmarks.rightShoulderY)  / 2;
    final baselineShoulderMidY = (calibration.leftShoulderY + calibration.rightShoulderY) / 2;
    final rawNTS      = (currentShoulderMidY  - landmarks.noseY)  / safeWidth;
    final baselineNTS = (baselineShoulderMidY - calibration.noseY) / safeBaselineWidth;

    if (_smoothNTS.isNaN) {
      _smoothNTS = rawNTS;
    } else {
      _smoothNTS = _ntsAlpha * rawNTS + (1 - _ntsAlpha) * _smoothNTS;
    }

    final ratioThreshold = calibration.headDropThreshold / safeBaselineWidth;
    // 0.35× (down from 0.50×): soft zone fires earlier so shoulder checks are
    // suppressed as soon as the phone starts moving, before the hard violation fires.
    final ratioSoft = ratioThreshold * 0.35;

    // headRise: nose above baseline (NTS increased)
    final ntsRise = (_smoothNTS - baselineNTS).clamp(0.0, double.infinity);
    final headRisePercent = (1.0 - ntsRise / ratioThreshold).clamp(0.0, 1.0) * 100;

    // headDrop: nose below baseline (NTS decreased)
    final ntsDrop = (baselineNTS - _smoothNTS).clamp(0.0, double.infinity);
    final headDropPercent = (1.0 - ntsDrop / ratioThreshold).clamp(0.0, 1.0) * 100;

    // Camera hysteresis: 65% exit (smooth EMA signal — tight band is fine).
    const cameraHysteresisExit = 0.65;
    if (ntsRise > ratioThreshold) {
      _headRaiseActive = true;
      _headDropActive  = false;
    } else if (_headRaiseActive && ntsRise < ratioThreshold * cameraHysteresisExit) {
      _headRaiseActive = false;
    }
    if (ntsDrop > ratioThreshold) {
      _headDropActive  = true;
      _headRaiseActive = false;
    } else if (_headDropActive && ntsDrop < ratioThreshold * cameraHysteresisExit) {
      _headDropActive = false;
    }

    final bool headRise = _headRaiseActive;
    final bool headDrop = _headDropActive;

    // ── Accelerometer: physical phone orientation ─────────────────────────────
    // Completely separate from camera NTS — only detects actual phone movement.
    //
    // Symmetric thresholds: 7° in either direction from calibration.
    const accelTooHighThreshRad = 7.0 * pi / 180;
    const accelTooLowThreshRad  = 7.0 * pi / 180;
    double phoneTooLowPercent  = 100.0;
    double phoneTooHighPercent = 100.0;

    if (accelX != null && accelY != null && accelZ != null) {
      final pitch = _signedPitch(
        calibration.accelX, calibration.accelY, calibration.accelZ,
        accelX, accelY, accelZ,
      );
      // positive pitch = phone tilted too low; negative = too high
      phoneTooLowPercent  = (1.0 - pitch.clamp(0.0, double.infinity)  / accelTooLowThreshRad).clamp(0.0, 1.0) * 100;
      phoneTooHighPercent = (1.0 - (-pitch).clamp(0.0, double.infinity) / accelTooHighThreshRad).clamp(0.0, 1.0) * 100;

      final pitchDeg = pitch * 180 / pi;
      // Separate hysteresis exits per direction:
      //   tooLow  50% exit — kept loose; phone-too-low is already confirmed working
      //   tooHigh 70% exit — tighter band keeps flag active even when EMA settles
      //                       slightly above the entry threshold after a quick lift
      if (pitchDeg > 7.0) {
        _accelTooLowActive  = true;
        _accelTooHighActive = false;
      } else if (_accelTooLowActive && pitchDeg < 7.0 * 0.70) {
        _accelTooLowActive = false;
      }
      if (pitchDeg < -7.0) {
        _accelTooHighActive = true;
        _accelTooLowActive  = false;
      } else if (_accelTooHighActive && pitchDeg > -7.0 * 0.70) {
        _accelTooHighActive = false;
      }
    }

    final bool phoneTooLow  = _accelTooLowActive;
    final bool phoneTooHigh = _accelTooHighActive;

    // ── Two-level suppression for body checks ─────────────────────────────────
    //
    // HARD extreme: an actual position violation is active, OR shoulders are
    // outside the reliable detection zone. Suppresses ALL body checks including
    // head tilt.
    final shouldersOffScreen =
        landmarks.leftShoulderY  > 0.88 || landmarks.rightShoulderY  > 0.88 ||
        landmarks.leftShoulderY  < 0.15 || landmarks.rightShoulderY  < 0.15;

    final hardExtreme =
        phoneTooHigh || phoneTooLow ||
        headRise || headDrop ||
        shouldersOffScreen;

    // SOFT extreme: NTS is drifting toward a hard violation but hasn't fired
    // yet. Perspective distortion already makes shoulder width/height less
    // reliable here, so suppress shoulder checks. Head tilt (ear Y diff) is
    // much less affected by NTS drift, so it is NOT suppressed by soft extreme.
    final softExtreme = hardExtreme || ntsDrop > ratioSoft || ntsRise > ratioSoft;

    // ── Head tilt with hysteresis ─────────────────────────────────────────────
    // Triggers only on left/right tilt (ear height difference vs baseline).
    // Only suppressed by hardExtreme — soft NTS drift should not hide a real tilt.
    final baselineEarDiff = (calibration.leftEarY  - calibration.rightEarY).abs();
    final currentEarDiff  = (landmarks.leftEarY    - landmarks.rightEarY).abs();
    final headTiltExcess  = (currentEarDiff - baselineEarDiff).clamp(0.0, double.infinity);
    final headTiltPercent = (1.0 - headTiltExcess / (calibration.headTiltThreshold * 2.0)).clamp(0.0, 1.0) * 100;

    if (!hardExtreme && headTiltExcess > calibration.headTiltThreshold) {
      _headTiltActive = true;
    } else if (_headTiltActive &&
               (hardExtreme || headTiltExcess < calibration.headTiltThreshold * cameraHysteresisExit)) {
      _headTiltActive = false;
    }
    final headTilt = _headTiltActive;

    // ── Shoulder asymmetry with hysteresis ────────────────────────────────────
    // Triggers only when one shoulder Y moves higher/lower than the other vs baseline.
    // Suppressed by softExtreme and by head tilt (a tilted head shifts shoulder readings).
    // Entry 0.04, exit 0.02 — prevents per-frame flickering.
    final leftDelta  = landmarks.leftShoulderY  - calibration.leftShoulderY;
    final rightDelta = landmarks.rightShoulderY - calibration.rightShoulderY;
    final shoulderAsymmetryExcess = (leftDelta - rightDelta).abs();
    const _shoulderYTrigger = 0.04;
    const _shoulderYExit    = 0.02;
    const _shoulderYZero    = 0.07;
    final shoulderSymmetryPercent = (1.0 - shoulderAsymmetryExcess / _shoulderYZero).clamp(0.0, 1.0) * 100;

    if (!softExtreme && !headTilt && shoulderAsymmetryExcess > _shoulderYTrigger) {
      _shoulderAsymmetryActive = true;
    } else if (_shoulderAsymmetryActive &&
               (softExtreme || headTilt || shoulderAsymmetryExcess < _shoulderYExit)) {
      _shoulderAsymmetryActive = false;
    }
    final shoulderAsymmetry = _shoulderAsymmetryActive;

    // ── Shoulder rounding with hysteresis ─────────────────────────────────────
    // Triggers only when both shoulder Xs come closer together (width narrowed).
    // Suppressed by softExtreme and head tilt only — NOT by shoulder asymmetry,
    // because hunching (X narrowing) and unevenness (Y difference) are independent
    // axes that can co-occur. Pure Y-asymmetry never narrows width, so excluding
    // shoulderAsymmetry here does not re-introduce false positives.
    // Entry 0.04, exit 0.02 — prevents per-frame flickering.
    final widthNarrowed = (calibration.shoulderWidth - currentShoulderWidth).clamp(0.0, double.infinity);
    const _roundingTrigger = 0.04;
    const _roundingExit    = 0.02;
    const _roundingZero    = 0.08;
    final shoulderRoundingPercent = (1.0 - widthNarrowed / _roundingZero).clamp(0.0, 1.0) * 100;

    // headRise excluded: shoulder narrowing shrinks safeWidth, which inflates
    // NTS and causes a spurious headRise that would otherwise block detection.
    final shoulderRoundingBlock = phoneTooHigh || phoneTooLow || headDrop || shouldersOffScreen;
    if (!shoulderRoundingBlock && !headTilt && widthNarrowed > _roundingTrigger) {
      _shoulderRoundingActive = true;
    } else if (_shoulderRoundingActive &&
               (shoulderRoundingBlock || headTilt || widthNarrowed < _roundingExit)) {
      _shoulderRoundingActive = false;
    }
    final shoulderRounding = _shoulderRoundingActive;

    final violations = (shoulderAsymmetry ? 1 : 0) +
        (headTilt ? 1 : 0) +
        (shoulderRounding ? 1 : 0) +
        (headRise ? 1 : 0) +
        (headDrop ? 1 : 0) +
        (phoneTooLow ? 1 : 0) +
        (phoneTooHigh ? 1 : 0);

    return PostureAnalysisResult(
      status: PostureStatus.fromViolationCount(violations),
      shoulderAsymmetry: shoulderAsymmetry,
      headTilt: headTilt,
      shoulderRounding: shoulderRounding,
      headRise: headRise,
      headDrop: headDrop,
      phoneTooLow: phoneTooLow,
      phoneTooHigh: phoneTooHigh,
      shoulderSymmetryPercent: shoulderSymmetryPercent,
      headTiltPercent: headTiltPercent,
      shoulderRoundingPercent: shoulderRoundingPercent,
      headRisePercent: headRisePercent,
      headDropPercent: headDropPercent,
      phoneTooLowPercent: phoneTooLowPercent,
      phoneTooHighPercent: phoneTooHighPercent,
    );
  }
}
