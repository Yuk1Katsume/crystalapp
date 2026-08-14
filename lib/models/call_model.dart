enum CallDirection { incoming, outgoing }
enum CallStatus { completed, rejected, missed }

class CallLog {
  final String id;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;
  final CallDirection direction;
  final CallStatus status;
  final int durationSeconds;
  final DateTime timestamp;
  final bool isVideo;

  CallLog({
    required this.id,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    required this.direction,
    required this.status,
    required this.durationSeconds,
    required this.timestamp,
    this.isVideo = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'caller_id': callerId,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'receiver_avatar': receiverAvatar,
      'direction': direction.name,
      'status': status.name,
      'duration_seconds': durationSeconds,
      'timestamp': timestamp.toIso8601String(),
      'is_video': isVideo ? 1 : 0,
    };
  }

  factory CallLog.fromMap(Map<String, dynamic> map) {
    return CallLog(
      id: map['id'] as String,
      callerId: map['caller_id'] as String? ?? '',
      callerName: map['caller_name'] as String? ?? 'Contacto',
      callerAvatar: map['caller_avatar'] as String?,
      receiverId: map['receiver_id'] as String? ?? '',
      receiverName: map['receiver_name'] as String? ?? 'Contacto',
      receiverAvatar: map['receiver_avatar'] as String?,
      direction: CallDirection.values.firstWhere(
        (e) => e.name == map['direction'],
        orElse: () => CallDirection.outgoing,
      ),
      status: CallStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => CallStatus.completed,
      ),
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
      isVideo: (map['is_video'] as int? ?? 0) == 1,
    );
  }

  String get otherUserName {
    if (direction == CallDirection.outgoing) {
      return receiverName;
    } else {
      return callerName;
    }
  }

  String? get otherUserAvatar {
    if (direction == CallDirection.outgoing) {
      return receiverAvatar;
    } else {
      return callerAvatar;
    }
  }

  String get otherUserId {
    if (direction == CallDirection.outgoing) {
      return receiverId;
    } else {
      return callerId;
    }
  }

  String get formattedDuration {
    if (status == CallStatus.missed || status == CallStatus.rejected || durationSeconds == 0) {
      return status == CallStatus.missed ? 'Perdida' : 'Rechazada';
    }
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    if (mins > 0) {
      return '${mins}m ${secs.toString().padLeft(2, '0')}s';
    } else {
      return '${secs}s';
    }
  }
}
