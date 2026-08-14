class StatusItem {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String type; // 'image', 'video', 'audio', 'text'
  final String content;
  final String? caption;
  final String backgroundColor;
  final List<String> allowedViewerIds;
  final List<String> viewedByUserIds;
  final DateTime createdAt;
  final DateTime expiresAt;

  StatusItem({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.type,
    required this.content,
    this.caption,
    this.backgroundColor = '#1E1E1E',
    required this.allowedViewerIds,
    this.viewedByUserIds = const [],
    required this.createdAt,
    required this.expiresAt,
  });

  bool isViewedBy(String uid) => viewedByUserIds.contains(uid);
  bool isExpired() => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_avatar_url': userAvatarUrl,
      'type': type,
      'content': content,
      'caption': caption,
      'background_color': backgroundColor,
      'allowed_viewer_ids': allowedViewerIds,
      'viewed_by_user_ids': viewedByUserIds,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  factory StatusItem.fromJson(Map<String, dynamic> json) {
    return StatusItem(
      id: json['id'] as String? ?? '',
      userId: (json['user_id'] ?? json['userId']) as String? ?? '',
      userName: (json['user_name'] ?? json['userName']) as String? ?? 'Usuario',
      userAvatarUrl: (json['user_avatar_url'] ?? json['userAvatarUrl']) as String?,
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      caption: json['caption'] as String?,
      backgroundColor: json['background_color'] as String? ?? json['backgroundColor'] as String? ?? '#1E1E1E',
      allowedViewerIds: List<String>.from(json['allowed_viewer_ids'] ?? json['allowedViewerIds'] ?? []),
      viewedByUserIds: List<String>.from(json['viewed_by_user_ids'] ?? json['viewedByUserIds'] ?? []),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }
}

/// A group of active statuses from a specific user
class UserStatusGroup {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<StatusItem> statuses;
  final DateTime lastUpdatedAt;

  UserStatusGroup({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.statuses,
    required this.lastUpdatedAt,
  });

  bool hasUnread(String currentUserId) {
    return statuses.any((s) => !s.isViewedBy(currentUserId));
  }
}
