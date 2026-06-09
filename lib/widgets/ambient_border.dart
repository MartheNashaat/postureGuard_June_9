// import 'package:flutter/material.dart';
// import '../models/posture_status.dart';

// class AmbientBorder extends StatelessWidget {
//   final PostureStatus status;
//   final double borderWidth;

//   const AmbientBorder({
//     super.key,
//     required this.status,
//     this.borderWidth = 4.0,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return IgnorePointer(
//       child: TweenAnimationBuilder<Color?>(
//         tween: ColorTween(end: status.color),
//         duration: const Duration(seconds: 2),
//         curve: Curves.easeInOut,
//         builder: (context, color, child) {
//           final c = color ?? Colors.green;
//           return Container(
//             decoration: BoxDecoration(
//               border: Border.all(
//                 color: c.withValues(alpha: 0.8),
//                 width: borderWidth,
//               ),
//               // Inner glow via box shadow
//               boxShadow: [
//                 BoxShadow(
//                   color: c.withValues(alpha: 0.3),
//                   blurRadius: 20,
//                   spreadRadius: -2,
//                   blurStyle: BlurStyle.inner,
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }
// }


// lib/widgets/ambient_border.dart


import 'package:flutter/material.dart';
import '../models/posture_status.dart';

class AmbientBorder extends StatelessWidget {
  final PostureStatus status;
  final double borderWidth;

  const AmbientBorder({
    super.key,
    required this.status,
    this.borderWidth = 12.0, 
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: status.color),
        duration: const Duration(milliseconds: 500),
        builder: (context, color, child) {
          final c = color ?? Colors.green;
          return Container(
            decoration: BoxDecoration(
              // MUST be null or transparent to see the camera
              color: Colors.transparent, 
              border: Border.all(
                // Use a lower opacity (0.3) to keep it subtle
                color: c.withOpacity(0.3), 
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.withOpacity(0.15),
                  blurRadius: 25,
                  spreadRadius: 2,
                  blurStyle: BlurStyle.inner, 
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}