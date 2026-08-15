// Message model for real-time chat with E2EE, Group, Image & Voice support

enum ChatMessageType {
  text,
  image,
  sticker,
  audio,
  system,
}

enum MessageStatus {
  pending,   // Clock icon (waiting/no internet)
  sent,      // 1 grey tick
  delivered, // 2 grey ticks
  read,      // 2 neon pink ticks (#FF1744 / Colors.pinkAccent)
}

class Message {
  final String id;
  final String text;
  final DateTime timestamp;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final String? recipientId;
  final String? groupId;
  final bool isEncrypted;
  final ChatMessageType type;
  final String? mediaUrl;
  final int? audioDurationSeconds;
  final String? audioWaveform;
  final bool isRead;
  final bool isStarred;
  final MessageStatus status;

  List<double>? get waveformList {
    if (audioWaveform == null || audioWaveform!.isEmpty) return null;
    try {
      return audioWaveform!
          .split(',')
          .map((e) => double.tryParse(e.trim()) ?? 0.15)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Message({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    this.recipientId,
    this.groupId,
    this.isEncrypted = true,
    this.type = ChatMessageType.text,
    this.mediaUrl,
    this.audioDurationSeconds,
    this.audioWaveform,
    this.isRead = false,
    this.isStarred = false,
    this.status = MessageStatus.sent,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'recipientId': recipientId,
      'groupId': groupId,
      'isEncrypted': isEncrypted,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'audioDurationSeconds': audioDurationSeconds,
      'audioWaveform': audioWaveform,
      'isRead': isRead,
      'isStarred': isStarred,
      'status': status.name,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String?,
      senderAvatar: json['senderAvatar'] as String?,
      recipientId: json['recipientId'] as String?,
      groupId: json['groupId'] as String?,
      isEncrypted: json['isEncrypted'] as bool? ?? true,
      type: ChatMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ChatMessageType.text,
      ),
      mediaUrl: json['mediaUrl'] as String?,
      audioDurationSeconds: json['audioDurationSeconds'] as int?,
      audioWaveform: json['audioWaveform'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      isStarred: json['isStarred'] as bool? ?? false,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class GroupModel {
  final String id;
  final String name;
  final String? description;
  final String? iconUrl;
  final List<String> memberIds;
  final String adminId;
  final DateTime createdAt;
  final String? wallpaperColor;
  final String? wallpaperImage;
  final double? wallpaperOpacity;

  GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.iconUrl,
    required this.memberIds,
    required this.adminId,
    required this.createdAt,
    this.wallpaperColor,
    this.wallpaperImage,
    this.wallpaperOpacity,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
      'memberIds': memberIds,
      'adminId': adminId,
      'createdAt': createdAt.toIso8601String(),
      'wallpaperColor': wallpaperColor,
      'wallpaperImage': wallpaperImage,
      'wallpaperOpacity': wallpaperOpacity,
    };
  }

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Group',
      description: json['description'] as String?,
      iconUrl: (json['iconUrl'] ?? json['icon_url']) as String?,
      memberIds: List<String>.from(json['memberIds'] ?? json['member_ids'] ?? []),
      adminId: (json['adminId'] ?? json['admin_id']) as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
      wallpaperColor: json['wallpaperColor'] as String?,
      wallpaperImage: json['wallpaperImage'] as String?,
      wallpaperOpacity: (json['wallpaperOpacity'] as num?)?.toDouble(),
    );
  }
}
