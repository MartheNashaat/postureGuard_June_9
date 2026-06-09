import 'dart:async';
import 'dart:io'; // Required for 'Platform'
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // 1. Setup the notification channel for Android
  if (Platform.isAndroid) {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'posture_guard_service', 
      'PostureGuard Service',
      description: 'Monitoring posture in background',
      importance: Importance.low, // Use low to avoid annoying sound every update
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // 2. Configure the service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, 
      isForegroundMode: true,
      notificationChannelId: 'posture_guard_service',
      initialNotificationTitle: 'PostureGuard Active',
      initialNotificationContent: 'Monitoring your posture...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async { // Added async here
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 3. Listen for status updates from the UI
  service.on('updateStatus').listen((event) async {
  if (service is AndroidServiceInstance) {
    if (await service.isForegroundService()) {
      // Use the '??' operator to provide safe fallbacks
      final String statusText = event?['status']?.toString() ?? "Monitoring";
      final String messageText = event?['message']?.toString() ?? "Session Active";

      service.setForegroundNotificationInfo(
        title: "Posture Guard: $statusText",
        content: messageText,
      );
    }
  }
});
  // 4. Background heartbeat timer
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) return;
    }
    print("PostureGuard Background Service Heartbeat");
  });
}