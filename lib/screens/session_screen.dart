import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/camera_service.dart';
import '../services/calibration_service.dart';
import '../services/database_service.dart';
import '../services/detection_service.dart';
import '../services/feedback_service.dart';
import '../services/posture_analyzer.dart';
import '../widgets/ambient_border.dart';
import '../widgets/camera_preview.dart' show CameraFeedView;
import '../widgets/score_meter.dart';
import '../widgets/skeleton_overlay.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../widgets/baseline_overlay.dart';
import '../services/overlay_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final DetectionService _detectionService = DetectionService();
  final FeedbackService _feedbackService = FeedbackService();
  
  bool _isLoading = true;
  String? _error;

  CalibrationData? _calibration;
  PostureAnalyzer? _analyzer;

  NormalizedLandmarks? _currentLandmarks;
  PostureStatus _currentStatus = PostureStatus.good;
  PostureAnalysisResult _currentResult = PostureAnalysisResult.good;

  late final String _sessionId;
  Timer? _logTimer;
  bool _isEnding = false;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _elapsedTimer;
  String _elapsedText = '00:00';

  bool _poseLost = false;
  DateTime? _lastPoseTime;
  
  // Track current score for UI updates
  double _currentScore = 100.0;
  
  Timer? _badPostureTimer;
  bool _isShowingOverlay = false;
  bool _isPipMode = false;   // updated each build(); guards native overlay visibility
  bool _wasPipMode = false;  // tracks previous frame's PiP state to detect transitions
  DateTime? _lastPipResumeTime; // debounce guard so both lifecycle + build() don't double-fire

  // Phone-angle monitoring
  StreamSubscription? _accelSubscription;
  bool _isAngleBad = false;
  bool _isAngleOverlayShowing = false;
  Timer? _angleBadTimer;
  double _currentAngleScore = 100.0;
  // EMA-smoothed accelerometer values (reduces sensor noise)
  double _smoothAccelX = 0, _smoothAccelY = 0, _smoothAccelZ = -9.8;
  bool _accelInitialized = false;
  Timer? _dimTimer;
  int? _originalBrightness;
  int _currentDimBrightness = 255;
  static const int _dimStep = 10;   // small step so each OS animation completes before next fires
  static const int _minBrightness = 5; // Never fully off — keeps OEM power mgmt from treating it as screen-off
  int? _originalScreenTimeout;

  // Combined score: only high when BOTH camera position AND phone angle match baseline.
  double get _combinedScore => _currentScore < _currentAngleScore ? _currentScore : _currentAngleScore;
  PostureStatus get _combinedStatus {
    if (_combinedScore >= 80) return PostureStatus.good;
    if (_combinedScore >= 50) return PostureStatus.warning;
    return PostureStatus.bad;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    unawaited(_preventScreenSleep());
    _init();
  }
  Future<void> _requestWriteSettingsPermission() async {
  final hasPermission = await OverlayService.isWriteSettingsEnabled();
  if (!hasPermission) {
    await OverlayService.requestWriteSettings();
  }
}

Future<void> _requestOverlayPermission() async {
    final hasPermission = await OverlayService.isOverlayEnabled();
    if (!hasPermission) {
      final requested = await OverlayService.requestOverlayPermission();
      if (requested && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable overlay permission in settings')),
        );
      }
    }
  }

Future<void> _init() async {
  await Future.delayed(const Duration(milliseconds: 500));
  _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  try {
    await _requestOverlayPermission();
    await _requestWriteSettingsPermission();
    _calibration = await CalibrationService.load();
    if (_calibration == null) {
      if (mounted) setState(() { _isLoading = false; _error = 'No calibration'; });
      return;
    }
    // SEND BASELINE TO OVERLAY - IMPORTANT!
    final baseline = _calibration!.asLandmarks;
    print('Sending baseline to overlay: noseX=${baseline.noseX}, noseY=${baseline.noseY}');
    
    await OverlayService.sendBaseline({
      'noseX': baseline.noseX,
      'noseY': baseline.noseY,
      'leftEarX': baseline.leftEarX,
      'leftEarY': baseline.leftEarY,
      'rightEarX': baseline.rightEarX,
      'rightEarY': baseline.rightEarY,
      'leftShoulderX': baseline.leftShoulderX,
      'leftShoulderY': baseline.leftShoulderY,
      'rightShoulderX': baseline.rightShoulderX,
      'rightShoulderY': baseline.rightShoulderY,
    });
    

      _analyzer = PostureAnalyzer(_calibration!);
      _startAngleMonitoring();
      await _feedbackService.initialize();
      await _cameraService.initialize();
      
      final service = FlutterBackgroundService();
      await service.startService();

      if (mounted) {
        setState(() => _isLoading = false);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cameraService.isInitialized) {
          _startDetection();
          _startLogging();
          _startElapsedTimer();
          _stopwatch.start();
        }
      });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'Camera Error: $e'; });
    }
  }

void _startDetection() {
  _cameraService.startImageStream((CameraImage image) async {
    if (_isEnding || !mounted) return;
    final desc = _cameraService.cameraDescription;
    if (desc == null) return;

    final landmarks = await _detectionService.processFrame(image, desc);

    // Reject ghost/background detections: shoulders must span at least 4% of frame width.
    // Real humans at normal distances show ~10–40%; background false-positives are far smaller.
    if (landmarks != null && landmarks.shoulderWidth < 0.04) return;

    if (landmarks != null && _analyzer != null && mounted) {
      _lastPoseTime = DateTime.now();
      final result = _analyzer!.analyze(
        landmarks,
        accelX: _accelInitialized ? _smoothAccelX : null,
        accelY: _accelInitialized ? _smoothAccelY : null,
        accelZ: _accelInitialized ? _smoothAccelZ : null,
      );
      _feedbackService.onFrame(result);

      // Use raw analyzer score directly — windowed average takes too long to recover
      _currentScore = result.overallScore;
      
      // Send posture update to overlay service
      await OverlayService.updatePosture(_combinedScore.round(), _combinedStatus.name);
      
      if (!mounted) return;
      
      // Determine status based on progressive score
      PostureStatus newStatus;
      if (_currentScore >= 80) {
        newStatus = PostureStatus.good;
      } else if (_currentScore >= 50) {
        newStatus = PostureStatus.warning;
      } else {
        newStatus = PostureStatus.bad;
      }

      // Handle bad posture timer for system overlay
      if (newStatus == PostureStatus.bad && _currentScore < 70) {
        // Start timer if not already running
        if (_badPostureTimer == null || !_badPostureTimer!.isActive) {
          _badPostureTimer?.cancel();
          _badPostureTimer = Timer(const Duration(seconds: 5), () async {
            if (!mounted || _currentScore >= 70) return;
            // Show native overlay in PiP / background at t+5s
            if (_isPipMode && !_isShowingOverlay) {
              _isShowingOverlay = true;
              await OverlayService.showGhostOverlay(_currentScore.round(), "bad");
            }
            // Dimming only in PiP mode for camera-posture violations
            if (mounted && _isPipMode && _currentScore < 70) unawaited(_startDimTimers());
          });
        }
      } else {
        // Posture improved - cancel timer, hide overlay, restore brightness
        if (_badPostureTimer != null && _badPostureTimer!.isActive) {
          _badPostureTimer?.cancel();
          _badPostureTimer = null;
        }
        if (_isShowingOverlay) {
          _isShowingOverlay = false;
        }
        // Only hide overlay and stop dimming if angle overlay is also not active
        await _hideAndDimIfClear();
      }

      // Only vibrate on really bad posture (score < 30)
      if (_currentScore < 30) {
        HapticFeedback.heavyImpact();
      }

      FlutterBackgroundService().invoke('updateStatus', {
        'status': newStatus.name.toUpperCase(),
        'score': _currentScore.round(),
        'message': result.violationMessages.isNotEmpty 
            ? result.violationMessages.first 
            : '${_currentScore.round()}% - Keep it up!',
      });

      setState(() {
        _currentLandmarks = landmarks;
        _currentStatus = newStatus;
        _currentResult = result;
        _poseLost = false;
      });
    } else if (landmarks == null && _lastPoseTime != null) {
      // Handle pose lost — after 4s of continuous non-detection, mark bad & reset score.
      // Guard with !_poseLost so we only apply the reset ONCE and don't call setState
      // on every null frame, which causes 0%↔real% flickering.
      final now = DateTime.now();
      if (!_poseLost && now.difference(_lastPoseTime!).inMilliseconds > 4000) {
        if (mounted) setState(() {
          _poseLost = true;
          _currentScore = 0;
          _currentStatus = PostureStatus.bad;
          _currentLandmarks = null;
        });
        await OverlayService.updatePosture(0, 'bad');
      }
    }
  });
}
 @override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    WakelockPlus.enable(); // Keep screen on during PiP / background
    // Show overlay if posture was already bad when entering background
    if (_cameraService.isInitialized &&
        _currentScore < 70 &&
        _badPostureTimer != null &&
        !_badPostureTimer!.isActive) {
      OverlayService.showGhostOverlay(_currentScore.round(), "bad");
      _isShowingOverlay = true;
      unawaited(_startDimTimers());
    }
    _stopwatch.stop();
  } else if (state == AppLifecycleState.resumed) {
    // Delegate to _onPipClosed which is also called via build() window-size tracking.
    // The debounce inside prevents double execution on older Android where
    // both the lifecycle event AND the build() transition fire.
    _onPipClosed();
  } else if (state == AppLifecycleState.detached) {
    _cameraService.dispose();
  }
}
  Future<void> _startDimTimers() async {
    _dimTimer?.cancel();
    // Only capture original brightness the first time; don't overwrite if already dimming
    if (_originalBrightness == null) {
      _originalBrightness = await OverlayService.getBrightness();
      _currentDimBrightness = _originalBrightness ?? 255;
    }

    // Apply first step immediately so the user sees dimming right away
    final firstNext = (_currentDimBrightness - _dimStep).clamp(_minBrightness, 255);
    if (firstNext < _currentDimBrightness) {
      _currentDimBrightness = firstNext;
      if (mounted) await OverlayService.setBrightness(_currentDimBrightness);
    }

    _dimTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (_currentDimBrightness - _dimStep).clamp(_minBrightness, 255);
      if (next == _currentDimBrightness) {
        timer.cancel();
        return;
      }
      _currentDimBrightness = next;
      await OverlayService.setBrightness(_currentDimBrightness);
    });
  }

  Future<void> _stopDimming() async {
    _dimTimer?.cancel();
    _dimTimer = null;
    if (_originalBrightness != null) {
      await OverlayService.setBrightness(_originalBrightness!);
      _currentDimBrightness = _originalBrightness!;
      _originalBrightness = null;
    }
  }

  // Disable the system screen-off timeout for the duration of the session so the
  // phone never sleeps while monitoring is active. Restored in _endSession / dispose.
  Future<void> _preventScreenSleep() async {
    _originalScreenTimeout = await OverlayService.getScreenTimeout();
    await OverlayService.setScreenTimeout(2147483647); // Int.MAX_VALUE — effectively never
  }

  Future<void> _restoreScreenSleep() async {
    if (_originalScreenTimeout != null) {
      await OverlayService.setScreenTimeout(_originalScreenTimeout!);
      _originalScreenTimeout = null;
    }
  }

  // ── Phone-angle monitoring ─────────────────────────────────────────────────

  void _startAngleMonitoring() {
    if (_calibration == null) return;
    _accelSubscription?.cancel();
    _accelInitialized = false; // reset EMA on each start
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 250),
    ).listen((event) {
      if (!mounted || _isEnding) return;
      // EMA smoothing (α=0.6): faster than 0.4 so phone-position violations
      // fire in ~300 ms instead of ~1.2 s. Still smooth enough to suppress
      // single-sample noise spikes (50% hysteresis in the analyzer handles the rest).
      if (!_accelInitialized) {
        _smoothAccelX = event.x;
        _smoothAccelY = event.y;
        _smoothAccelZ = event.z;
        _accelInitialized = true;
      } else {
        const alpha = 0.6;
        _smoothAccelX = alpha * event.x + (1 - alpha) * _smoothAccelX;
        _smoothAccelY = alpha * event.y + (1 - alpha) * _smoothAccelY;
        _smoothAccelZ = alpha * event.z + (1 - alpha) * _smoothAccelZ;
      }
      final diff = _angleDiff(
        _calibration!.accelX, _calibration!.accelY, _calibration!.accelZ,
        _smoothAccelX, _smoothAccelY, _smoothAccelZ,
      );
      // Score: 100% at 0°, 0% at 30°
      _currentAngleScore = ((1.0 - diff / 30.0).clamp(0.0, 1.0) * 100);
      _onAngleUpdate(diff > 15.0);
    });
  }

  void _onAngleUpdate(bool angleBad) {
    if (angleBad && !_isAngleBad) {
      // Angle just went bad — start 5-second grace timer
      _isAngleBad = true;
      _angleBadTimer?.cancel();
      _angleBadTimer = Timer(const Duration(seconds: 5), () async {
        if (!mounted || !_isAngleBad) return;
        if (_isPipMode && !_isAngleOverlayShowing && !_isShowingOverlay) {
          _isAngleOverlayShowing = true;
          await OverlayService.showGhostOverlay(_currentAngleScore.round(), "bad");
        }
        // Dimming starts immediately after the ghost skeleton appears
        if (mounted && _isAngleBad) unawaited(_startDimTimers());
      });
    } else if (_isAngleOverlayShowing) {
      // Overlay visible — update score live every tick
      OverlayService.updatePosture(_combinedScore.round(), _combinedStatus.name);
      // Hide once angle is back within ~3° of baseline (85% with EMA smoothing)
      if (_currentAngleScore >= 85) {
        _isAngleBad = false;
        _angleBadTimer?.cancel();
        _angleBadTimer = null;
        _isAngleOverlayShowing = false;
        unawaited(_hideAndDimIfClear());
      }
    } else if (!angleBad && _isAngleBad) {
      // Corrected before overlay appeared — cancel grace timer
      _isAngleBad = false;
      _angleBadTimer?.cancel();
      _angleBadTimer = null;
    }
  }

  Future<void> _hideAndDimIfClear() async {
    if (!_isShowingOverlay && !_isAngleOverlayShowing) {
      await OverlayService.hideOverlay();
      await _stopDimming();
    }
  }

  double _angleDiff(double bx, double by, double bz,
                    double cx, double cy, double cz) {
    final bLen = sqrt(bx * bx + by * by + bz * bz);
    final cLen = sqrt(cx * cx + cy * cy + cz * cz);
    if (bLen == 0 || cLen == 0) return 0;
    final dot = (bx * cx + by * cy + bz * cz) / (bLen * cLen);
    return acos(dot.clamp(-1.0, 1.0)) * 180 / pi;
  }

  // ── PiP-close / resume handler ────────────────────────────────────────────

  /// Called both from the lifecycle resumed event AND from the build() PiP-size
  /// transition so it fires on every Android version regardless of whether PiP
  /// triggers lifecycle callbacks.
  void _onPipClosed() {
    if (!mounted || _isEnding) return;
    // Debounce: if both the lifecycle callback and build() fire within 1 s, only run once
    final now = DateTime.now();
    if (_lastPipResumeTime != null &&
        now.difference(_lastPipResumeTime!).inMilliseconds < 6000) return;
    _lastPipResumeTime = now;

    WakelockPlus.enable();
    unawaited(_preventScreenSleep()); // re-assert never-sleep when returning to full-screen angle mode
    _isShowingOverlay = false;
    _isAngleOverlayShowing = false;
    _isAngleBad = false;
    _angleBadTimer?.cancel();
    _angleBadTimer = null;
    _badPostureTimer?.cancel();
    _badPostureTimer = null;
    unawaited(OverlayService.hideOverlay());
    unawaited(_stopDimming());
    _lastPoseTime = null;
    _poseLost = false;
    _feedbackService.reset();
    _currentAngleScore = 100.0;
    // Keep the accel subscription alive to avoid sensor delivery gaps; just reset EMA state.
    // If the subscription somehow died, restart it.
    if (_accelSubscription != null) {
      _accelInitialized = false;
    } else {
      _startAngleMonitoring();
    }
    if (_cameraService.isInitialized && !_isEnding) {
      unawaited(_cameraService.stopImageStream().then((_) {
        if (mounted && !_isEnding) _startDetection();
      }));
    }
    if (!_stopwatch.isRunning) _stopwatch.start();
  }

  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _endSession() async {
    final confirmed = await _showEndConfirmation();
    if (confirmed != true) return;

    setState(() {
      _isEnding = true;
      _currentLandmarks = null;
    });

    _logTimer?.cancel();
    _elapsedTimer?.cancel();
    _angleBadTimer?.cancel();
    _accelSubscription?.cancel();
    _stopwatch.stop();
    await _stopDimming();
    await _restoreScreenSleep();
    await OverlayService.hideOverlay();

    FlutterBackgroundService().invoke('stopService');
    await _cameraService.stopImageStream();
    await _cameraService.dispose();

    final summary = await DatabaseService.endSession(_sessionId);
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.pushReplacementNamed(context, '/summary', arguments: summary);
    }
  }

  Future<bool> _onWillPop() async {
    final result = await _showEndConfirmation();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isPip = MediaQuery.of(context).size.width < 300;
    // Window-size transition is reliable on ALL Android versions (lifecycle events are not)
    if (_wasPipMode && !isPip && !_isEnding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPipClosed());
    }
    _wasPipMode = isPip;
    _isPipMode = isPip;

    if (isPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            CameraFeedView(
              controller: _cameraService.controller,
              overlays: [
                if (_calibration != null)
                  BaselineOverlay(baseline: _calibration!.asLandmarks),
                if (_currentLandmarks != null)
                  Opacity(
                    opacity: _combinedStatus == PostureStatus.bad ? 0.4 : 0.9,
                    child: SkeletonOverlay(
                      landmarks: _currentLandmarks!,
                      status: _combinedStatus,
                    ),
                  ),
              ],
            ),
            // Show red tint based on combined score severity
            if (_combinedScore < 50)
              Container(color: Colors.red.withOpacity(0.3 - (_combinedScore / 100) * 0.3)),
            // Show combined score in PiP mode
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_combinedScore.round()}%',
                  style: TextStyle(
                    color: _getScoreColor(_combinedScore),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
      ),
    );
  }
  Widget _buildBody() {
  final controller = _cameraService.controller;

  if (_isLoading || controller == null || !controller.value.isInitialized) {
    return const Center(child: CircularProgressIndicator());
  }

  return SafeArea(
    child: Stack(
      fit: StackFit.expand,
      children: [
        // THE CAMERA VIEW
        CameraFeedView(
          controller: controller,
          overlays: [
            if (_calibration != null)
              BaselineOverlay(
                baseline: _calibration!.asLandmarks,
                showInstructions: false,
              ),
            if (_currentLandmarks != null)
              SkeletonOverlay(
                landmarks: _currentLandmarks!,
                status: _combinedStatus,
              ),
          ],
        ),

        // Visual Penalty Tint
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            color: _combinedStatus == PostureStatus.bad
                ? Colors.red.withOpacity(0.2)
                : Colors.transparent,
          ),
        ),

        // Ambient border and HUD components
        AmbientBorder(status: _combinedStatus),
        if (_poseLost) _buildPoseLostWarning(),
        _buildHUD(),
        _buildControls(),
      ],
    ),
  );
}

// Add this new method to show a pulsing ghost guide when posture is bad
Widget _buildPulsingGhostGuide() {
  return IgnorePointer(
    child: Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        builder: (context, opacity, child) {
          return Opacity(
            opacity: opacity,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.teal.withOpacity(0.6),
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              margin: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // The ghost overlay inside the highlighted area
                    BaselineOverlay(
                      baseline: _calibration!.asLandmarks,
                      showInstructions: true,
                    ),
                    // Semi-transparent overlay to dim everything but the ghost
                    Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
    // --- Updated UI Components with Progressive Scoring ---

  Widget _buildHUD() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Column(
        children: [
          _buildTimerBadge(),
          const SizedBox(height: 8),
          _buildStreakBadge(),
          if (_currentResult.violationCount > 0)
            _buildViolationBadge(),
        ],
      ),
    );
  }

  Widget _buildHeadDirectionBadge({required bool up}) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.orange.withOpacity(0.6)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          color: Colors.orange,
          size: 13,
        ),
        const SizedBox(width: 4),
        Text(
          up ? 'Head rise' : 'Head drop',
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _buildPhoneTooHighHint() => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withOpacity(0.6)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber, color: Colors.red, size: 13),
        SizedBox(width: 4),
        Text(
          'Phone too high — lower it',
          style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
Widget _buildControls() {
  return Stack(
    children: [
      // Score Meter at bottom
      Positioned(
        bottom: 161,
        left: 0,
        right: 0,
        child: ScoreMeter(score: _combinedScore / 100),
      ),

      // Rule indicators
      Positioned(
        bottom: 116,
        left: 16,
        right: 16,
        child: _buildRuleIndicators(),
      ),

      // End Session button
      Positioned(
        bottom: 40,
        left: 24,
        right: 24,
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isEnding ? null : _endSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              _isEnding ? 'Saving...' : 'End Session', 
              style: const TextStyle(fontSize: 18, color: Colors.white)
            ),
          ),
        ),
      ),
    ],
  );
}
  // New: Score badge showing percentage
  Widget _buildScoreBadge() {
    final scoreColor = _getScoreColor(_combinedScore);
    final scoreText = '${_combinedScore.round()}%';
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scoreColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: scoreColor.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            scoreText,
            style: TextStyle(
              color: scoreColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getScoreMessage(_combinedScore),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54, 
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min, 
      children: [
        const Icon(Icons.timer, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(
          _elapsedText, 
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16),
        ),
      ],
    ),
  );

  Widget _buildStreakBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54, 
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
        const SizedBox(width: 4),
        Text(
          _streakText(), 
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildViolationBadge() => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black87, 
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withOpacity(0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber, color: Colors.orange, size: 14),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _currentResult.violationMessages.join(' • '), 
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _buildPoseLostWarning() => Center(
    child: AnimatedOpacity(
      opacity: _poseLost ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87, 
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(Icons.person_search, color: Colors.orange, size: 48),
            SizedBox(height: 12),
            Text(
              'Pose Lost',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Please return to frame',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildErrorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min, 
      children: [
        const Icon(Icons.error, color: Colors.red, size: 48),
        const SizedBox(height: 16),
        Text(
          _error ?? 'Unknown Error', 
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context), 
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('Go Back'),
        ),
      ],
    ),
  );

  String _getScoreMessage(double score) {
    if (score >= 90) return 'Excellent Posture!';
    if (score >= 75) return 'Good Posture';
    if (score >= 60) return 'Slight Adjustment Needed';
    if (score >= 40) return 'Needs Improvement';
    if (score >= 20) return 'Poor Posture';
    return 'Critical - Fix Now!';
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _statusText() {
    if (_currentLandmarks == null) return 'Looking for pose...';
    if (_combinedScore >= 80) return 'EXCELLENT';
    if (_combinedScore >= 60) return 'GOOD';
    if (_combinedScore >= 40) return 'FAIR';
    if (_combinedScore >= 20) return 'POOR';
    return 'CRITICAL';
  }

  String _streakText() {
    final minutes = _feedbackService.goodStreakMinutes;
    final seconds = _feedbackService.goodStreakSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s streak';
    }
    return '${seconds}s streak';
  }

  Widget _buildRuleIndicators() {
    final bool phonePositionBad = _currentResult.phoneTooHigh || _currentResult.phoneTooLow ||
        _currentResult.headDrop || _currentResult.headRise;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        if (!phonePositionBad) ...[
          _buildProgressiveRuleChip(
            'Shoulders',
            !_currentResult.shoulderAsymmetry,
            _currentResult.shoulderSymmetryPercent,
          ),
          _buildProgressiveRuleChip(
            'Head Tilt',
            !_currentResult.headTilt,
            _currentResult.headTiltPercent,
          ),
          _buildProgressiveRuleChip(
            'Hunching',
            !_currentResult.shoulderRounding,
            _currentResult.shoulderRoundingPercent,
          ),
        ],
      ],
    );
  }

  // Progressive rule chip that shows percentage
  Widget _buildProgressiveRuleChip(String label, bool passing, double percent) {
    Color chipColor;
    if (passing) {
      chipColor = Colors.green.withOpacity(0.6);
    } else if (percent >= 50) {
      chipColor = Colors.orange.withOpacity(0.6);
    } else {
      chipColor = Colors.red.withOpacity(0.6);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor, 
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label, 
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          if (!passing) ...[
            const SizedBox(width: 4),
            Text(
              '${percent.round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  void _startLogging() {
    _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      DatabaseService.logEvent(sessionId: _sessionId, status: _currentStatus);
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final elapsed = _stopwatch.elapsed;
        _elapsedText = '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
        if (_lastPoseTime != null) {
          _poseLost = DateTime.now().difference(_lastPoseTime!).inSeconds > 3;
        }
      });
    });
  }

  Future<bool?> _showEndConfirmation() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('End Session?'),
      content: Text('Your posture score: ${_combinedScore.round()}%'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false), 
          child: const Text('Continue'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true), 
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('End'),
        ),
      ],
    ),
  );

@override
void dispose() {
  _badPostureTimer?.cancel();
  _angleBadTimer?.cancel();
  _accelSubscription?.cancel();
  _dimTimer?.cancel();
  _logTimer?.cancel();
  _elapsedTimer?.cancel();
  unawaited(_restoreScreenSleep());
  WidgetsBinding.instance.removeObserver(this);
  _cameraService.dispose();
  _detectionService.dispose();
  _feedbackService.dispose();
  super.dispose();
}
}