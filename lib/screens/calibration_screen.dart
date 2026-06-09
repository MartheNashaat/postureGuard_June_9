import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/posture_status.dart';
import '../services/camera_service.dart';
import '../services/calibration_service.dart';
import '../services/detection_service.dart';
import '../widgets/camera_preview.dart' show CameraFeedView;
import '../widgets/skeleton_overlay.dart';
import '../widgets/baseline_overlay.dart'; // <-- MAKE SURE THIS LINE EXISTS


enum _CalibrationPhase { preview, countdown, complete, failed }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final DetectionService _detectionService = DetectionService();
  final CalibrationService _calibrationService = CalibrationService();

  bool _isLoading = true;
  String? _error;

  _CalibrationPhase _phase = _CalibrationPhase.preview;
  bool _poseDetected = false;
  NormalizedLandmarks? _currentLandmarks;

  // Countdown state
  int _secondsRemaining = 5;
  Timer? _countdownTimer;
  int _samplesCollected = 0;

  // Accelerometer baseline collection
  StreamSubscription? _accelSub;
  final List<double> _accelXSamples = [];
  final List<double> _accelYSamples = [];
  final List<double> _accelZSamples = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _cameraService.initialize();
      _startDetection();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Camera error: $e';
        });
      }
    }
  }

  // void _startDetection() {
  //   _cameraService.startImageStream((CameraImage image) async {
  //     final landmarks = await _detectionService.processFrame(
  //       image,
  //       _cameraService.cameraDescription!,
  //     );

  //     if (!mounted) return;

  //     if (landmarks != null) {
  //       // Collect samples during countdown phase
  //       if (_phase == _CalibrationPhase.countdown) {
  //         _calibrationService.addSample(landmarks);
  //         _samplesCollected = _calibrationService.sampleCount;
  //       }

  //       setState(() {
  //         _poseDetected = true;
  //         _currentLandmarks = landmarks;
  //       });
  //     } else {
  //       if (_poseDetected) {
  //         setState(() => _poseDetected = false);
  //       }
  //     }
  //   });
  // }
Timer? _poseLostTimer; // Add this to your state class

void _startDetection() {
  _cameraService.startImageStream((CameraImage image) async {
    final landmarks = await _detectionService.processFrame(
      image,
      _cameraService.cameraDescription!,
    );

    if (!mounted) return;

    if (landmarks != null) {
      _poseLostTimer?.cancel();
      _poseLostTimer = null; // Clean up timer reference

      // ADD THIS PART: Collect samples during countdown phase
      if (_phase == _CalibrationPhase.countdown) {
        _calibrationService.addSample(landmarks);
        // We use a local variable or update state to reflect the count
        _samplesCollected = _calibrationService.sampleCount;
      }

      setState(() {
        _poseDetected = true;
        _currentLandmarks = landmarks;
      });
    } else {
      // Don't lose the pose immediately; wait 500ms
      _poseLostTimer ??= Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _poseDetected = false;
            _currentLandmarks = null;
          });
        }
      });
    }
  });
}

  void _startCalibration() {
    _calibrationService.reset();
    _accelXSamples.clear();
    _accelYSamples.clear();
    _accelZSamples.clear();
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((e) {
      _accelXSamples.add(e.x);
      _accelYSamples.add(e.y);
      _accelZSamples.add(e.z);
    });
    setState(() {
      _phase = _CalibrationPhase.countdown;
      _secondsRemaining = 5;
      _samplesCollected = 0;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _secondsRemaining--);

      if (_secondsRemaining <= 0) {
        timer.cancel();
        _finishCalibration();
      }
    });
  }

  // Future<void> _finishCalibration() async {
  //   final baseline = _calibrationService.computeBaseline();

  //   if (baseline == null || _samplesCollected < 10) {
  //     setState(() => _phase = _CalibrationPhase.failed);
  //     return;
  //   }

  //   await _calibrationService.save(baseline);

  //   if (!mounted) return;

  //   setState(() => _phase = _CalibrationPhase.complete);

  //   // Brief pause to show success, then navigate
  //   await Future.delayed(const Duration(milliseconds: 800));
  //   if (mounted) {
  //     Navigator.pushReplacementNamed(context, '/session');
  //   }
  // }
//  Future<void> _finishCalibration() async {
//   final baseline = _calibrationService.computeBaseline();

//   if (baseline == null || _samplesCollected < 10) {
//     setState(() => _phase = _CalibrationPhase.failed);
//     return;
//   }

//   // 1. Stop the camera stream first!
//   await _cameraService.stopImageStream();
//   // 2. Dispose the controller entirely
//   await _cameraService.dispose(); 

//   await _calibrationService.save(baseline);

//   if (!mounted) return;
//   setState(() => _phase = _CalibrationPhase.complete);

//   await Future.delayed(const Duration(milliseconds: 500));
//   if (mounted) {
//     Navigator.pushReplacementNamed(context, '/session');
//   }
// } 
Future<void> _finishCalibration() async {
  _accelSub?.cancel();
  _accelSub = null;
  double _avg(List<double> l) =>
      l.isEmpty ? 0.0 : l.reduce((a, b) => a + b) / l.length;
  final baseline = _calibrationService.computeBaseline(
    accelX: _avg(_accelXSamples),
    accelY: _avg(_accelYSamples),
    accelZ: _accelZSamples.isEmpty ? -9.8 : _avg(_accelZSamples),
  );
  if (baseline == null || _samplesCollected < 10) {
    setState(() => _phase = _CalibrationPhase.failed);
    return;
  }

  // STOP the stream, but don't dispose the controller yet 
  // if you plan to reuse it, OR ensure the UI stops rendering first.
  await _cameraService.stopImageStream();
  
  await _calibrationService.save(baseline);

  if (!mounted) return;
  setState(() => _phase = _CalibrationPhase.complete);

  await Future.delayed(const Duration(milliseconds: 500));
  if (mounted) {
    // Navigate first
    Navigator.pushReplacementNamed(context, '/session');
  }
}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _countdownTimer?.cancel();
      _accelSub?.cancel();
      _accelSub = null;
      _calibrationService.reset();
      if (mounted) setState(() {
        _isLoading = true;
        // If locked mid-countdown, reset to preview so detection doesn't
        // keep collecting samples on resume with no timer to finish
        if (_phase == _CalibrationPhase.countdown) {
          _phase = _CalibrationPhase.preview;
          _samplesCollected = 0;
        }
      });
      _cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() { _isLoading = true; _error = null; });
      _initCamera();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _accelSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    _detectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting camera...',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _initCamera();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed with skeleton
          // In _buildBody method, add BaselineOverlay to the camera preview overlays
          CameraFeedView(
            controller: _cameraService.controller!,
            overlays: [
              // Show ghost baseline preview during calibration
              if (_phase == _CalibrationPhase.preview && _currentLandmarks != null)
                BaselineOverlay(
                  baseline: _currentLandmarks,
                  showInstructions: _phase == _CalibrationPhase.preview,
                ),
              if (_currentLandmarks != null)
                SkeletonOverlay(
                  landmarks: _currentLandmarks!,
                  status: PostureStatus.good,
                ),
            ],
          ),

          // Top bar
          _buildTopBar(),

          // Center status indicator
          _buildCenterIndicator(),

          // Bottom panel
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _phase == _CalibrationPhase.countdown
                  ? null
                  : () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back,
                  color: _phase == _CalibrationPhase.countdown
                      ? Colors.grey
                      : Colors.white),
            ),
            const Expanded(
              child: Text(
                'Calibration',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterIndicator() {
    switch (_phase) {
      case _CalibrationPhase.preview:
        return _buildStatusBadge(
          color: _poseDetected
              ? Colors.green.withValues(alpha: 0.7)
              : Colors.orange.withValues(alpha: 0.7),
          icon: _poseDetected ? Icons.check_circle : Icons.search,
          text: _poseDetected
              ? 'Pose detected'
              : 'Position yourself in frame',
        );

      case _CalibrationPhase.countdown:
        return Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Large countdown number
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withValues(alpha: 0.8),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Center(
                  child: Text(
                    '$_secondsRemaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (5 - _secondsRemaining) / 5,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.teal),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_samplesCollected samples collected',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        );

      case _CalibrationPhase.complete:
        return _buildStatusBadge(
          color: Colors.green.withValues(alpha: 0.8),
          icon: Icons.check_circle,
          text: 'Calibration complete!',
        );

      case _CalibrationPhase.failed:
        return _buildStatusBadge(
          color: Colors.red.withValues(alpha: 0.8),
          icon: Icons.error,
          text: 'Not enough data — keep your pose visible',
        );
    }
  }

  Widget _buildStatusBadge({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(text,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _phase == _CalibrationPhase.countdown
                  ? 'Hold still...'
                  : 'Sit up straight and hold your phone naturally',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _phase == _CalibrationPhase.countdown
                  ? 'Collecting your posture baseline'
                  : 'Make sure your face and shoulders are visible',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: _buildActionButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_phase) {
      case _CalibrationPhase.preview:
        return ElevatedButton(
          onPressed: _poseDetected ? _startCalibration : null,
          style: _buttonStyle(Colors.teal),
          child: Text(
            _poseDetected ? 'Begin Calibration' : 'Waiting for pose...',
            style: const TextStyle(fontSize: 18),
          ),
        );

      case _CalibrationPhase.countdown:
        return ElevatedButton(
          onPressed: null,
          style: _buttonStyle(Colors.grey),
          child: const Text('Calibrating...',
              style: TextStyle(fontSize: 18)),
        );

      case _CalibrationPhase.complete:
        return ElevatedButton(
          onPressed: null,
          style: _buttonStyle(Colors.green),
          child: const Text('Starting session...',
              style: TextStyle(fontSize: 18)),
        );

      case _CalibrationPhase.failed:
        return ElevatedButton(
          onPressed: () {
            setState(() => _phase = _CalibrationPhase.preview);
          },
          style: _buttonStyle(Colors.orange),
          child: const Text('Try Again', style: TextStyle(fontSize: 18)),
        );
    }
  }

  ButtonStyle _buttonStyle(Color bg) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      disabledBackgroundColor: bg.withValues(alpha: 0.5),
      disabledForegroundColor: Colors.white70,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
