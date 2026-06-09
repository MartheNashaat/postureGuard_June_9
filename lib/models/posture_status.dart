import 'package:flutter/material.dart';

enum PostureStatus {
  good,
  warning,
  bad;

  int get value {
    switch (this) {
      case PostureStatus.good:
        return 0;
      case PostureStatus.warning:
        return 1;
      case PostureStatus.bad:
        return 2;
    }
  }

  Color get color {
    switch (this) {
      case PostureStatus.good:
        return Colors.green;
      case PostureStatus.warning:
        return Colors.yellow;
      case PostureStatus.bad:
        return Colors.red;
    }
  }

  static PostureStatus fromViolationCount(int violations) {
    if (violations == 0) return PostureStatus.good;
    if (violations == 1) return PostureStatus.warning;
    return PostureStatus.bad;
  }

  static PostureStatus fromValue(int value) {
    switch (value) {
      case 0:
        return PostureStatus.good;
      case 1:
        return PostureStatus.warning;
      default:
        return PostureStatus.bad;
    }
  }
}
