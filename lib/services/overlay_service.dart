// lib/services/overlay_service.dart
import 'package:flutter/services.dart';

class OverlayService {
  static const MethodChannel _channel = MethodChannel('com.postureguard/overlay');
  
  static Future<bool> requestOverlayPermission() async {
    try {
      final bool result = await _channel.invokeMethod('requestOverlayPermission');
      return result;
    } catch (e) {
      print('Error requesting overlay permission: $e');
      return false;
    }
  }
  
  static Future<bool> isOverlayEnabled() async {
    try {
      final bool result = await _channel.invokeMethod('isOverlayEnabled');
      return result;
    } catch (e) {
      return false;
    }
  }
  
  static Future<void> updatePosture(int score, String status) async {
    try {
      await _channel.invokeMethod('updatePosture', {
        'score': score,
        'status': status,
      });
    } catch (e) {
      print('Error updating posture: $e');
    }
  }
  
  // FIXED: Send baseline as Map<String, double>
  static Future<void> sendBaseline(Map<String, double> landmarks) async {
    try {
      print('Sending baseline to native: $landmarks'); // Debug print
      await _channel.invokeMethod('updateBaseline', landmarks);
      print('Baseline sent successfully');
    } catch (e) {
      print('Error sending baseline: $e');
    }
  }
  
  static Future<bool> showGhostOverlay(int score, String status) async {
    try {
      await _channel.invokeMethod('showOverlay', {'show': true});
      await _channel.invokeMethod('updatePosture', {
        'score': score,
        'status': status,
      });
      return true;
    } catch (e) {
      print('Error showing overlay: $e');
      return false;
    }
  }
  
  static Future<void> hideOverlay() async {
    try {
      await _channel.invokeMethod('showOverlay', {'show': false});
    } catch (e) {
      print('Error hiding overlay: $e');
    }
  }

  static Future<int> getBrightness() async {
    try {
      final int value = await _channel.invokeMethod('getBrightness');
      return value;
    } catch (e) {
      return 255;
    }
  }

  static Future<void> setBrightness(int brightness) async {
    try {
      await _channel.invokeMethod('setBrightness', {'brightness': brightness});
    } catch (e) {
      print('Error setting brightness: $e');
    }
  }

  static Future<bool> isWriteSettingsEnabled() async {
    try {
      final bool value = await _channel.invokeMethod('isWriteSettingsEnabled');
      return value;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestWriteSettings() async {
    try {
      await _channel.invokeMethod('requestWriteSettings');
    } catch (e) {
      print('Error requesting write settings: $e');
    }
  }

  static Future<int> getScreenTimeout() async {
    try {
      final int value = await _channel.invokeMethod('getScreenTimeout');
      return value;
    } catch (e) {
      return 30000;
    }
  }

  static Future<void> setScreenTimeout(int timeout) async {
    try {
      await _channel.invokeMethod('setScreenTimeout', {'timeout': timeout});
    } catch (e) {
      print('Error setting screen timeout: $e');
    }
  }
}