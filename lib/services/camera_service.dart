import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize({
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    _cameras = await availableCameras();

    final frontCamera = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );

    // ML Kit requires NV21 on Android, bgra8888 on iOS
    final imageFormat = Platform.isAndroid
        ? ImageFormatGroup.nv21
        : ImageFormatGroup.bgra8888;

    _controller = CameraController(
      frontCamera,
      resolution,
      enableAudio: false,
      imageFormatGroup: imageFormat,
    );

    await _controller!.initialize();
  }

  void startImageStream(void Function(CameraImage image) onImage) {
    if (_controller == null || !isInitialized) return;
    _controller!.startImageStream(onImage);
  }

  Future<void> stopImageStream() async {
    if (_controller == null || !isInitialized) return;
    try {
      await _controller!.stopImageStream();
    } catch (e) {
      debugPrint('CameraService: stopImageStream error: $e');
    }
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  CameraDescription? get cameraDescription {
    if (_controller == null) return null;
    return _controller!.description;
  }
}
