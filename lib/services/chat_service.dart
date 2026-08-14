import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../models/message_model.dart';
import 'e2ee_service.dart';
import 'local_database_service.dart';
import 'supabase_config.dart';

/// Prefix that signals the encrypted_content field contains an embedded image
const String _imgPayloadPrefix = 'IMGENC:';
const String _audioPayloadPrefix = 'AUDENC:';
/// Max bytes to embed directly in the message payload (~1.5 MB raw → ~2 MB base64)
const int _maxEmbedBytes = 1500000;

class ChatService {
  SupabaseClient get _supabase => SupabaseConfig.client;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  String get currentUserId => fb_auth.FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Stream Direct E2EE Messages using Local SQLite
  Stream<List<Message>> getChatMessagesWithUser(String recipientId) {
    final chatId = getChatId(currentUserId, recipientId);
    final controller = StreamController<List<Message>>();

    // 1. Emit local SQLite history immediately
    _localDb.getLocalMessages(chatId).then((localMsgs) {
      if (!controller.isClosed) controller.add(localMsgs);
    });

    // 2. Listen to real-time incoming E2EE messages from Supabase for OTHER users
    final subscription = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', chatId)
        .order('created_at', ascending: true)
        .listen((data) async {
          bool hasNewIncoming = false;

          for (var item in data) {
            final senderId = item['sender_id'];
            // Skip messages sent by oneself (already in local SQLite)
            if (senderId == currentUserId) continue;

            final msgId = item['id'].toString();
            final encryptedContent = item['encrypted_content'] as String? ?? '';
            final messageType = item['message_type'] ?? 'text';

            String decryptedText;
            String? localMediaPath;

            if (messageType == 'image' && encryptedContent.startsWith(_imgPayloadPrefix)) {
              // Image is embedded in the payload as encrypted base64
              decryptedText = '📷 Imagen';
              localMediaPath = await _extractAndSaveEmbeddedImage(encryptedContent, msgId, chatId);
            } else if (messageType == 'audio' && (encryptedContent.startsWith(_audioPayloadPrefix) || encryptedContent.startsWith('AUDENC_URL:'))) {
              // Voice note is encrypted with E2EE
              decryptedText = '🎤 Mensaje de voz';
              localMediaPath = await _extractAndSaveEmbeddedAudio(encryptedContent, msgId, chatId);
            } else if (messageType == 'sticker') {
              decryptedText = '🎨 Sticker';
              localMediaPath = E2EEService.decryptPayload(encryptedContent, chatId);
            } else {
              decryptedText = E2EEService.decryptPayload(encryptedContent, chatId);
            }

            await _localDb.saveLocalMessage(
              id: msgId,
              senderId: senderId,
              recipientId: item['recipient_id'],
              groupId: chatId,
              text: decryptedText,
              messageType: messageType,
              mediaUrl: localMediaPath,
              createdAt: DateTime.parse(item['created_at']),
              isRead: false,
              status: 'delivered',
            );

            // Delete consumed message from Supabase relay
            try {
              await _supabase.from('messages').delete().eq('id', item['id']);
            } catch (_) {}

            hasNewIncoming = true;
          }

          if (hasNewIncoming) {
            final updatedLocalMsgs = await _localDb.getLocalMessages(chatId);
            if (!controller.isClosed) controller.add(updatedLocalMsgs);
          }
        });

    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }

  /// Decodes and saves an embedded encrypted image payload to local storage
  Future<String?> _extractAndSaveEmbeddedImage(
      String payload, String msgId, String chatId) async {
    try {
      final base64Data = payload.substring(_imgPayloadPrefix.length);
      final encryptedBytes = Uint8List.fromList(base64Decode(base64Data));
      final decryptedBytes = E2EEService.decryptBytes(encryptedBytes, chatId);

      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/img_received_$msgId.jpg');
      await localFile.writeAsBytes(decryptedBytes);
      return localFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Decodes and saves an embedded encrypted audio payload to local storage
  Future<String?> _extractAndSaveEmbeddedAudio(
      String payload, String msgId, String chatId) async {
    try {
      Uint8List? encryptedBytes;
      if (payload.startsWith(_audioPayloadPrefix)) {
        final base64Data = payload.substring(_audioPayloadPrefix.length);
        encryptedBytes = Uint8List.fromList(base64Decode(base64Data));
      } else if (payload.startsWith('AUDENC_URL:')) {
        final url = payload.substring(11);
        final res = await HttpClient().getUrl(Uri.parse(url));
        final response = await res.close();
        final bytesList = <int>[];
        await for (var chunk in response) {
          bytesList.addAll(chunk);
        }
        encryptedBytes = Uint8List.fromList(bytesList);
      }

      if (encryptedBytes != null) {
        final decryptedBytes = E2EEService.decryptBytes(encryptedBytes, chatId);
        final dir = await getApplicationDocumentsDirectory();
        final localFile = File('${dir.path}/vn_received_$msgId.m4a');
        await localFile.writeAsBytes(decryptedBytes);
        return localFile.path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete message permanently from local SQLite
  Future<void> deleteMessage(String msgId) async {
    await _localDb.deleteLocalMessage(msgId);
  }

  /// Send Direct E2EE Encrypted Message via Supabase relay + Save locally in SQLite
  Future<void> sendDirectMessage({
    required String recipientId,
    required String text,
    String? mediaUrl,
    bool isSticker = false,
    ChatMessageType type = ChatMessageType.text,
    int? audioDurationSeconds,
  }) async {
    final chatId = getChatId(currentUserId, recipientId);
    final msgId = '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    String messageType;
    if (type == ChatMessageType.audio || (mediaUrl != null && (mediaUrl.endsWith('.m4a') || mediaUrl.endsWith('.aac')))) {
      messageType = 'audio';
    } else if (isSticker || type == ChatMessageType.sticker) {
      messageType = 'sticker';
    } else if (mediaUrl != null || type == ChatMessageType.image) {
      messageType = 'image';
    } else {
      messageType = 'text';
    }

    // 1. Save locally in SQLite as pending / sent
    await _localDb.saveLocalMessage(
      id: msgId,
      senderId: currentUserId,
      recipientId: recipientId,
      groupId: chatId,
      text: text,
      messageType: messageType,
      mediaUrl: mediaUrl,
      createdAt: now,
      status: 'pending',
    );

    // 2. Build encrypted payload for Supabase relay
    String encryptedContent;

    if (messageType == 'audio' && mediaUrl != null && File(mediaUrl).existsSync()) {
      final rawBytes = await File(mediaUrl).readAsBytes();
      final encryptedBytes = E2EEService.encryptBytes(rawBytes, chatId);
      final base64Data = base64Encode(encryptedBytes);
      encryptedContent = '$_audioPayloadPrefix$base64Data';
    } else if (isSticker && mediaUrl != null) {
      encryptedContent = E2EEService.encryptPayload(mediaUrl, chatId);
    } else if (mediaUrl != null && File(mediaUrl).existsSync()) {
      // Embed encrypted image bytes directly in the payload
      final rawBytes = await File(mediaUrl).readAsBytes();
      final bytesToSend = rawBytes.length > _maxEmbedBytes
          ? rawBytes.sublist(0, _maxEmbedBytes)
          : rawBytes;
      final encryptedBytes = E2EEService.encryptBytes(bytesToSend, chatId);
      final base64Data = base64Encode(encryptedBytes);
      encryptedContent = '$_imgPayloadPrefix$base64Data';
    } else if (mediaUrl != null && mediaUrl.startsWith('http')) {
      encryptedContent = E2EEService.encryptPayload(mediaUrl, chatId);
    } else {
      encryptedContent = E2EEService.encryptPayload(text, chatId);
    }

    final payload = <String, dynamic>{
      'sender_id': currentUserId,
      'recipient_id': recipientId,
      'group_id': chatId,
      'encrypted_content': encryptedContent,
      'message_type': messageType,
      'created_at': now.toIso8601String(),
    };

    try {
      await _supabase.from('messages').insert(payload);
      await _localDb.updateMessageStatus(msgId, 'sent');
    } catch (_) {
      // If offline/error, remains pending
    }
  }

  /// Generates unique direct chat conversation ID
  String getChatId(String uid1, String uid2) {
    final list = [uid1, uid2]..sort();
    return '${list[0]}_${list[1]}';
  }
}
