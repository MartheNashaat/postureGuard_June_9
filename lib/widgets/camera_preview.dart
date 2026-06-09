// lib/widgets/camera_preview.dart

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraFeedView extends StatelessWidget {
  final CameraController? controller; // Change to nullable
  final List<Widget> overlays;

  const CameraFeedView({
    super.key,
    required this.controller,
    this.overlays = const [],
  });
@override
Widget build(BuildContext context) {
  // GUARD 1: If the controller is null or disposing, don't crash.
  if (controller == null || !controller!.value.isInitialized) {
    return Container(color: Colors.black); // Show black instead of red
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      // GUARD 2: Access previewSize safely. No '!' here.
      final size = controller!.value.previewSize;
      if (size == null) return Container(color: Colors.black);

      final previewAspectRatio = size.height / size.width;

      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxWidth / previewAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // GUARD 3: Wrap the preview in a try-catch for hardware hiccups
                  _safePreview(),
                  ...overlays,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _safePreview() {
  try {
    return controller!.buildPreview();
  } catch (e) {
    return Container(color: Colors.black);
  }
}
}