import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';

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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT,
            recipient_id TEXT,
            group_id TEXT,
            text TEXT,
            message_type TEXT,
            media_url TEXT,
            audio_duration INTEGER,
            created_at TEXT,
            is_read INTEGER DEFAULT 1,
            is_starred INTEGER DEFAULT 0,
            status TEXT DEFAULT 'sent'
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
      },
    );
  }

  /// Save message locally on the device
  Future<void> saveLocalMessage({
    required String id,
    required String senderId,
    required String recipientId,
    required String groupId,
    required String text,
    required String messageType,
    String? mediaUrl,
    int? audioDurationSeconds,
    required DateTime createdAt,
    bool isRead = true,
    bool isStarred = false,
    String status = 'sent',
  }) async {
    final database = await db;
    await database.insert(
      'local_messages',
      {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'group_id': groupId,
        'text': text,
        'message_type': messageType,
        'media_url': mediaUrl,
        'audio_duration': audioDurationSeconds,
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
  Future<void> markMessagesAsRead(String groupId) async {
    final database = await db;
    await database.update(
      'local_messages',
      {'is_read': 1, 'status': 'read'},
      where: 'group_id = ? AND is_read = 0',
      whereArgs: [groupId],
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
    }

    final statusStr = item['status'] as String? ?? 'sent';
    final status = MessageStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => MessageStatus.sent,
    );

    return Message(
      id: item['id'] as String,
      senderId: item['sender_id'] as String,
      recipientId: item['recipient_id'] as String?,
      text: item['text'] as String,
      timestamp: DateTime.parse(item['created_at'] as String),
      type: type,
      mediaUrl: item['media_url'] as String?,
      audioDurationSeconds: item['audio_duration'] as int?,
      isRead: (item['is_read'] as int? ?? 1) == 1,
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
}
