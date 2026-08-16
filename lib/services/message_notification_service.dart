import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MessageNotificationService {
  static final MessageNotificationService _instance = MessageNotificationService._internal();
  factory MessageNotificationService() => _instance;
  MessageNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Tracks active open chat to suppress heads-up notification if user is currently looking at it
  String? activeChatId;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handled via foreground navigation or intent
      },
    );

    _isInitialized = true;
  }

  /// Show a WhatsApp-styled notification for incoming direct messages or group messages
  Future<void> showIncomingMessageNotification({
    required String senderId,
    required String senderName,
    required String messageText,
    required String chatId,
    required bool isGroup,
    String? groupName,
  }) async {
    // If the user is currently inside this chat, do not annoy with a notification
    if (activeChatId != null && activeChatId == chatId) {
      return;
    }

    await initialize();

    final title = isGroup && groupName != null && groupName.isNotEmpty
        ? '$senderName en $groupName'
        : senderName;

    final androidDetails = AndroidNotificationDetails(
      'crystal_messages_channel_v1',
      'Mensajes y Grupos',
      channelDescription: 'Notificaciones de mensajes privados y grupales al estilo WhatsApp',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
      styleInformation: BigTextStyleInformation(
        messageText,
        htmlFormatBigText: false,
        contentTitle: title,
        htmlFormatContentTitle: false,
        summaryText: isGroup ? groupName : 'Nuevo mensaje',
      ),
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(android: androidDetails);

    // Unique notification ID per conversation so messages from the same sender stack cleanly
    final notifId = chatId.hashCode.abs();

    await _notificationsPlugin.show(
      notifId,
      title,
      messageText,
      details,
      payload: chatId,
    );
  }

  Future<void> cancelNotification(String chatId) async {
    try {
      await _notificationsPlugin.cancel(chatId.hashCode.abs());
    } catch (_) {}
  }
}
