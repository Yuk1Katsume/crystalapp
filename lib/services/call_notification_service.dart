import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CallNotificationService {
  static final CallNotificationService _instance = CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handled via app navigation / foreground streams
      },
    );

    _isInitialized = true;
  }

  Future<void> showIncomingCallNotification({
    required int notificationId,
    required String callerName,
    required bool isVideo,
    required String callId,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      'crystal_incoming_calls_v2',
      'Llamadas Entrantes',
      channelDescription: 'Canal prioritario para llamadas de voz y video en tiempo real',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      playSound: true,
    );

    final details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      notificationId,
      'Llamada entrante de $callerName 🌸',
      isVideo ? 'Llamada de video cifrada E2EE' : 'Llamada de voz cifrada E2EE',
      details,
      payload: callId,
    );
  }

  Future<void> cancelCallNotification(int notificationId) async {
    try {
      await _notificationsPlugin.cancel(notificationId);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
  }
}
