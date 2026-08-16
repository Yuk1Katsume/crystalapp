import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';
import '../models/call_model.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'crystal_chat_local.db');

    return await openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT,
            sender_name TEXT,
            sender_avatar TEXT,
            recipient_id TEXT,
            group_id TEXT,
            text TEXT,
            message_type TEXT,
            media_url TEXT,
            audio_duration INTEGER,
            audio_waveform TEXT,
            created_at TEXT,
            is_read INTEGER DEFAULT 1,
            is_starred INTEGER DEFAULT 0,
            status TEXT DEFAULT 'sent'
          )
        ''');
        await db.execute('''
          CREATE TABLE call_logs (
            id TEXT PRIMARY KEY,
            caller_id TEXT,
            caller_name TEXT,
            caller_avatar TEXT,
            receiver_id TEXT,
            receiver_name TEXT,
            receiver_avatar TEXT,
            direction TEXT,
            status TEXT,
            duration_seconds INTEGER,
            timestamp TEXT,
            is_video INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE favorite_conversations (
            conversation_id TEXT PRIMARY KEY,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE viewed_statuses (
            status_id TEXT PRIMARY KEY,
            viewed_at TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN is_read INTEGER DEFAULT 1');
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute("ALTER TABLE local_messages ADD COLUMN status TEXT DEFAULT 'sent'");
          } catch (_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN is_starred INTEGER DEFAULT 0');
          } catch (_) {}
        }
        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN audio_duration INTEGER');
          } catch (_) {}
        }
        if (oldVersion < 6) {
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN audio_waveform TEXT');
          } catch (_) {}
        }
        if (oldVersion < 7) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS call_logs (
                id TEXT PRIMARY KEY,
                caller_id TEXT,
                caller_name TEXT,
                caller_avatar TEXT,
                receiver_id TEXT,
                receiver_name TEXT,
                receiver_avatar TEXT,
                direction TEXT,
                status TEXT,
                duration_seconds INTEGER,
                timestamp TEXT,
                is_video INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS favorite_conversations (
                conversation_id TEXT PRIMARY KEY,
                created_at TEXT
              )
            ''');
          } catch (_) {}
        }
        if (oldVersion < 8) {
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN sender_name TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE local_messages ADD COLUMN sender_avatar TEXT');
          } catch (_) {}
        }
        if (oldVersion < 9) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS viewed_statuses (
                status_id TEXT PRIMARY KEY,
                viewed_at TEXT
              )
            ''');
          } catch (_) {}
        }
      },
    );
  }

  /// Save message locally on the device
  Future<void> saveLocalMessage({
    required String id,
    required String senderId,
    String? senderName,
    String? senderAvatar,
    required String recipientId,
    required String groupId,
    required String text,
    required String messageType,
    String? mediaUrl,
    int? audioDurationSeconds,
    String? audioWaveform,
    required DateTime createdAt,
    bool isRead = false,
    bool isStarred = false,
    String status = 'sent',
  }) async {
    final database = await db;
    await database.insert(
      'local_messages',
      {
        'id': id,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_avatar': senderAvatar,
        'recipient_id': recipientId,
        'group_id': groupId,
        'text': text,
        'message_type': messageType,
        'media_url': mediaUrl,
        'audio_duration': audioDurationSeconds,
        'audio_waveform': audioWaveform,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead ? 1 : 0,
        'is_starred': isStarred ? 1 : 0,
        'status': status,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update message status (e.g. pending -> sent -> delivered -> read)
  Future<void> updateMessageStatus(String id, String status) async {
    final database = await db;
    await database.update(
      'local_messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Toggle starred status for a message
  Future<void> toggleStarredMessage(String id, bool isStarred) async {
    final database = await db;
    await database.update(
      'local_messages',
      {'is_starred': isStarred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark all messages in a conversation as read
  Future<void> markMessagesAsRead(String conversationId) async {
    final database = await db;
    await database.update(
      'local_messages',
      {'is_read': 1, 'status': 'read'},
      where: '(group_id = ? OR sender_id = ? OR recipient_id = ?) AND is_read = 0',
      whereArgs: [conversationId, conversationId, conversationId],
    );
  }

  /// Mark a single message as read
  Future<void> markSingleMessageAsRead(String messageId) async {
    final database = await db;
    await database.update(
      'local_messages',
      {'is_read': 1, 'status': 'read'},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Retrieve distinct user IDs with whom there are active conversations
  Future<List<String>> getActiveConversationUserIds(String currentUserId) async {
    final database = await db;
    final res = await database.rawQuery('''
      SELECT DISTINCT 
        CASE 
          WHEN sender_id = ? THEN recipient_id 
          ELSE sender_id 
        END as other_user_id
      FROM local_messages
      WHERE (sender_id = ? OR recipient_id = ?) 
        AND (group_id NOT LIKE 'group_%' OR group_id IS NULL)
    ''', [currentUserId, currentUserId, currentUserId]);

    final ids = <String>{};
    for (var r in res) {
      final id = r['other_user_id'] as String?;
      if (id != null && id.isNotEmpty && id != currentUserId) {
        ids.add(id);
      }
    }
    return ids.toList();
  }

  /// Clear all messages in a conversation / group
  Future<void> clearChatMessages(String conversationId) async {
    final database = await db;
    await database.delete(
      'local_messages',
      where: 'group_id = ? OR sender_id = ? OR recipient_id = ?',
      whereArgs: [conversationId, conversationId, conversationId],
    );
  }

  /// Delete a conversation / group completely from local database
  Future<void> deleteConversation(String conversationId) async {
    final database = await db;
    await database.delete(
      'local_messages',
      where: 'group_id = ? OR sender_id = ? OR recipient_id = ?',
      whereArgs: [conversationId, conversationId, conversationId],
    );
    await database.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Retrieve local chat history for a conversation
  Future<List<Message>> getLocalMessages(String groupId) async {
    final database = await db;
    final maps = await database.query(
      'local_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at ASC',
    );

    return maps.map((item) => _mapToMessage(item)).toList();
  }

  /// Retrieve all starred messages for a conversation
  Future<List<Message>> getStarredMessages(String groupId) async {
    final database = await db;
    final maps = await database.query(
      'local_messages',
      where: 'group_id = ? AND is_starred = 1',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );

    return maps.map((item) => _mapToMessage(item)).toList();
  }

  /// Retrieve all media (images, voice, files - excluding stickers) for a conversation
  Future<List<Message>> getMediaMessages(String groupId) async {
    final database = await db;
    final maps = await database.query(
      'local_messages',
      where: "group_id = ? AND ((message_type = 'image' AND text != '🎨 Sticker') OR message_type = 'audio' OR message_type = 'file')",
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );

    return maps.map((item) => _mapToMessage(item)).toList();
  }

  Message _mapToMessage(Map<String, dynamic> item) {
    final msgType = item['message_type'] as String?;
    ChatMessageType type = ChatMessageType.text;
    if (msgType == 'sticker') {
      type = ChatMessageType.sticker;
    } else if (msgType == 'image') {
      type = ChatMessageType.image;
    } else if (msgType == 'audio') {
      type = ChatMessageType.audio;
    } else if (msgType == 'system') {
      type = ChatMessageType.system;
    }

    final statusStr = item['status'] as String? ?? 'sent';
    final status = MessageStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => MessageStatus.sent,
    );

    return Message(
      id: item['id'] as String,
      senderId: item['sender_id'] as String,
      senderName: item['sender_name'] as String?,
      senderAvatar: item['sender_avatar'] as String?,
      recipientId: item['recipient_id'] as String?,
      groupId: item['group_id'] as String?,
      text: item['text'] as String,
      timestamp: DateTime.parse(item['created_at'] as String),
      type: type,
      mediaUrl: item['media_url'] as String?,
      audioDurationSeconds: item['audio_duration'] as int?,
      audioWaveform: item['audio_waveform'] as String?,
      isRead: (item['is_read'] as int? ?? 0) == 1,
      isStarred: (item['is_starred'] as int? ?? 0) == 1,
      status: status,
    );
  }

  /// Delete local message by id
  Future<void> deleteLocalMessage(String id) async {
    final database = await db;
    await database.delete(
      'local_messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get total count of unread incoming messages
  Future<int> getTotalUnreadCount(String currentUserId) async {
    final database = await db;
    final res = await database.rawQuery('''
      SELECT COUNT(*) as unread_count 
      FROM local_messages 
      WHERE is_read = 0 AND sender_id != ?
    ''', [currentUserId]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// Get the last message for a conversation (for home screen preview)
  Future<Map<String, dynamic>?> getLastMessage(String groupId) async {
    final database = await db;
    final maps = await database.query(
      'local_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// ----------------------------------------
  /// Call Logs Methods
  /// ----------------------------------------
  Future<void> saveCallLog(CallLog log) async {
    final database = await db;
    await database.insert(
      'call_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CallLog>> getCallLogs() async {
    final database = await db;
    final maps = await database.query(
      'call_logs',
      orderBy: 'timestamp DESC',
    );
    return maps.map((e) => CallLog.fromMap(e)).toList();
  }

  Future<void> deleteCallLog(String id) async {
    final database = await db;
    await database.delete(
      'call_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllCallLogs() async {
    final database = await db;
    await database.delete('call_logs');
  }

  /// ----------------------------------------
  /// Favorite Conversations Methods
  /// ----------------------------------------
  Future<void> toggleFavorite(String conversationId, bool isFav) async {
    final database = await db;
    if (isFav) {
      await database.insert(
        'favorite_conversations',
        {
          'conversation_id': conversationId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await database.delete(
        'favorite_conversations',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
    }
  }

  Future<bool> isConversationFavorite(String conversationId) async {
    final database = await db;
    final maps = await database.query(
      'favorite_conversations',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<Set<String>> getFavoriteConversationIds() async {
    final database = await db;
    final maps = await database.query('favorite_conversations');
    return maps.map((e) => e['conversation_id'] as String).toSet();
  }

  /// Get list of user IDs / group IDs that have unread messages
  Future<Set<String>> getUnreadConversationIds(String currentUserId) async {
    final database = await db;
    final maps = await database.rawQuery('''
      SELECT DISTINCT group_id, sender_id 
      FROM local_messages 
      WHERE is_read = 0 AND sender_id != ?
    ''', [currentUserId]);

    final result = <String>{};
    for (final row in maps) {
      if (row['group_id'] != null) result.add(row['group_id'] as String);
      if (row['sender_id'] != null) result.add(row['sender_id'] as String);
    }
    return result;
  }

  /// Get unread message count for a single conversation
  Future<int> getUnreadCountForConversation(String conversationId, String currentUserId) async {
    final database = await db;
    final res = await database.rawQuery('''
      SELECT COUNT(*) as unread_count 
      FROM local_messages 
      WHERE (group_id = ? OR sender_id = ?) AND is_read = 0 AND sender_id != ?
    ''', [conversationId, conversationId, currentUserId]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// ----------------------------------------
  /// Viewed Statuses Methods (Local Persistence)
  /// ----------------------------------------
  Future<void> markStatusAsViewedLocally(String statusId) async {
    final database = await db;
    await database.insert(
      'viewed_statuses',
      {
        'status_id': statusId,
        'viewed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> getViewedStatusIds() async {
    final database = await db;
    final maps = await database.query('viewed_statuses');
    return maps.map((e) => e['status_id'] as String).toSet();
  }

  Future<bool> isStatusViewedLocally(String statusId) async {
    final database = await db;
    final maps = await database.query(
      'viewed_statuses',
      where: 'status_id = ?',
      whereArgs: [statusId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }
}

