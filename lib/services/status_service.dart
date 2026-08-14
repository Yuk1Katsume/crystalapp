import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/status_model.dart';
import 'contacts_service.dart';
import 'e2ee_service.dart';
import 'local_database_service.dart';
import 'supabase_config.dart';

class StatusService {
  static final StatusService _instance = StatusService._internal();
  factory StatusService() => _instance;
  StatusService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ContactsServiceManager _contactsService = ContactsServiceManager();

  static const String _statusSecretSalt = 'crystal_status_e2ee_salt_v1';

  /// Computes mutual allowed viewer IDs:
  /// 1. Bilateral active conversations (users with direct message history in SQLite or Supabase).
  /// 2. Registered contacts from device address book.
  Future<List<String>> getMutualAllowedViewerIds() async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return [];

    final allowedIds = <String>{};

    // 1. Bilateral active chat conversations from SQLite
    try {
      final activeChatUserIds = await _localDb.getActiveConversationUserIds(currentUid);
      allowedIds.addAll(activeChatUserIds);
    } catch (_) {}

    // 2. Direct message conversations from Supabase
    try {
      final sent = await SupabaseConfig.client
          .from('messages')
          .select('recipient_id')
          .eq('sender_id', currentUid)
          .limit(100);
      for (final row in sent) {
        if (row['recipient_id'] != null && row['recipient_id'].toString().isNotEmpty) {
          allowedIds.add(row['recipient_id'].toString());
        }
      }
      final received = await SupabaseConfig.client
          .from('messages')
          .select('sender_id')
          .eq('recipient_id', currentUid)
          .limit(100);
      for (final row in received) {
        if (row['sender_id'] != null && row['sender_id'].toString().isNotEmpty) {
          allowedIds.add(row['sender_id'].toString());
        }
      }
    } catch (_) {}

    // 3. Mutual phone contacts
    try {
      final res = await _contactsService.syncContacts();
      final registered = res['registered'] ?? [];
      for (final c in registered) {
        if (c.appUserId != null && c.appUserId!.isNotEmpty && c.appUserId != currentUid) {
          allowedIds.add(c.appUserId!);
        }
      }
    } catch (_) {}

    return allowedIds.toList();
  }

  /// Publishes a new End-to-End Encrypted Status
  Future<StatusItem?> publishStatus({
    required String type, // 'image', 'video', 'audio', 'text'
    required String content, // Base64 or plain content to encrypt
    String? caption,
    String backgroundColor = '#1E1E1E',
  }) async {
    final user = _auth.currentUser;
    final currentUid = user?.uid;
    if (currentUid == null || currentUid.isEmpty) return null;

    String userName = user?.displayName ?? user?.phoneNumber ?? 'Usuario';
    String? userAvatar = user?.photoURL;

    try {
      final profile = await SupabaseConfig.client
          .from('users')
          .select('display_name, username, avatar_url')
          .eq('id', currentUid)
          .maybeSingle();
      if (profile != null) {
        if (profile['display_name'] != null && profile['display_name'].toString().isNotEmpty) {
          userName = profile['display_name'];
        } else if (profile['username'] != null && profile['username'].toString().isNotEmpty) {
          userName = profile['username'];
        }
        if (profile['avatar_url'] != null && profile['avatar_url'].toString().isNotEmpty) {
          userAvatar = profile['avatar_url'];
        }
      }
    } catch (_) {}

    final allowedViewerIds = await getMutualAllowedViewerIds();
    final docRef = _firestore.collection('statuses').doc();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    // Encrypt content & caption for E2EE storage
    final encryptedContent = E2EEService.encryptPayload(content, _statusSecretSalt);
    final encryptedCaption = caption != null && caption.isNotEmpty
        ? E2EEService.encryptPayload(caption, _statusSecretSalt)
        : null;

    final status = StatusItem(
      id: docRef.id,
      userId: currentUid,
      userName: userName,
      userAvatarUrl: userAvatar,
      type: type,
      content: encryptedContent,
      caption: encryptedCaption,
      backgroundColor: backgroundColor,
      allowedViewerIds: allowedViewerIds,
      viewedByUserIds: [],
      createdAt: now,
      expiresAt: expiresAt,
    );

    // 1. Save to Firestore with timeout
    try {
      await docRef.set(status.toJson()).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Persist to Supabase statuses table
    try {
      await SupabaseConfig.client.from('statuses').upsert({
        'id': status.id,
        'user_id': status.userId,
        'user_name': status.userName,
        'user_avatar_url': status.userAvatarUrl,
        'type': status.type,
        'content': status.content,
        'caption': status.caption,
        'background_color': status.backgroundColor,
        'allowed_viewer_ids': status.allowedViewerIds,
        'viewed_by_user_ids': status.viewedByUserIds,
        'created_at': status.createdAt.toIso8601String(),
        'expires_at': status.expiresAt.toIso8601String(),
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}

    return status;
  }

  /// Real-time stream of contact status updates (only active, non-expired, and allowed for current user)
  Stream<List<UserStatusGroup>> getRecentStatusesStream() {
    final currentUid = _auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return Stream.value([]);

    // Trigger background cleanup of expired statuses
    pruneExpiredStatuses();

    return _firestore
        .collection('statuses')
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final validStatuses = <StatusItem>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final status = StatusItem.fromJson(data);

          // Only keep if not expired (strict 24h cycle)
          if (status.expiresAt.isBefore(now)) continue;

          // Exclude own statuses (handled separately)
          if (status.userId == currentUid) continue;

          // Check if current user is in allowed viewers list or public mutual
          if (status.allowedViewerIds.isEmpty || status.allowedViewerIds.contains(currentUid)) {
            // Decrypt content
            final decryptedContent = E2EEService.decryptPayload(status.content, _statusSecretSalt);
            final decryptedCaption = status.caption != null
                ? E2EEService.decryptPayload(status.caption!, _statusSecretSalt)
                : null;

            validStatuses.add(StatusItem(
              id: status.id,
              userId: status.userId,
              userName: status.userName,
              userAvatarUrl: status.userAvatarUrl,
              type: status.type,
              content: decryptedContent,
              caption: decryptedCaption,
              backgroundColor: status.backgroundColor,
              allowedViewerIds: status.allowedViewerIds,
              viewedByUserIds: status.viewedByUserIds,
              createdAt: status.createdAt,
              expiresAt: status.expiresAt,
            ));
          }
        } catch (_) {}
      }

      // Group statuses by user
      final grouped = <String, List<StatusItem>>{};
      for (final s in validStatuses) {
        grouped.putIfAbsent(s.userId, () => []).add(s);
      }

      final result = <UserStatusGroup>[];
      for (final entry in grouped.entries) {
        final list = entry.value;
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        result.add(UserStatusGroup(
          userId: entry.key,
          userName: list.first.userName,
          userAvatarUrl: list.first.userAvatarUrl,
          statuses: list,
          lastUpdatedAt: list.last.createdAt,
        ));
      }

      // Sort contact groups with unread statuses first, then by last updated
      result.sort((a, b) {
        final aUnread = a.hasUnread(currentUid);
        final bUnread = b.hasUnread(currentUid);
        if (aUnread && !bUnread) return -1;
        if (!aUnread && bUnread) return 1;
        return b.lastUpdatedAt.compareTo(a.lastUpdatedAt);
      });

      return result;
    });
  }

  /// Real-time stream of current user's own active statuses
  Stream<List<StatusItem>> getMyStatusesStream() {
    final currentUid = _auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return Stream.value([]);

    return _firestore
        .collection('statuses')
        .where('user_id', isEqualTo: currentUid)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final myStatuses = <StatusItem>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final status = StatusItem.fromJson(data);
          if (status.expiresAt.isAfter(now)) {
            final decryptedContent = E2EEService.decryptPayload(status.content, _statusSecretSalt);
            final decryptedCaption = status.caption != null
                ? E2EEService.decryptPayload(status.caption!, _statusSecretSalt)
                : null;

            myStatuses.add(StatusItem(
              id: status.id,
              userId: status.userId,
              userName: status.userName,
              userAvatarUrl: status.userAvatarUrl,
              type: status.type,
              content: decryptedContent,
              caption: decryptedCaption,
              backgroundColor: status.backgroundColor,
              allowedViewerIds: status.allowedViewerIds,
              viewedByUserIds: status.viewedByUserIds,
              createdAt: status.createdAt,
              expiresAt: status.expiresAt,
            ));
          }
        } catch (_) {}
      }

      myStatuses.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return myStatuses;
    });
  }

  /// Mark status as viewed by current user
  Future<void> markStatusAsViewed(String statusId) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return;

    try {
      await _firestore.collection('statuses').doc(statusId).update({
        'viewed_by_user_ids': FieldValue.arrayUnion([currentUid]),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Prune and remove expired statuses (> 24 hours old) from both Firestore and Supabase
  Future<void> pruneExpiredStatuses() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    try {
      final oldDocs = await _firestore
          .collection('statuses')
          .where('created_at', isLessThan: cutoff.toIso8601String())
          .get();
      for (final doc in oldDocs.docs) {
        await doc.reference.delete();
      }
    } catch (_) {}

    try {
      await SupabaseConfig.client
          .from('statuses')
          .delete()
          .lt('created_at', cutoff.toIso8601String());
    } catch (_) {}
  }

  /// Delete status by ID
  Future<void> deleteStatus(String statusId) async {
    try {
      await _firestore.collection('statuses').doc(statusId).delete();
      try {
        await SupabaseConfig.client.from('statuses').delete().eq('id', statusId);
      } catch (_) {}
    } catch (_) {}
  }
}
