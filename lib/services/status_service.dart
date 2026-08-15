import 'dart:async';
import 'dart:convert';
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

  /// Computes mutual allowed viewer IDs
  Future<List<String>> getMutualAllowedViewerIds() async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return [];

    final allowedIds = <String>{};

    try {
      final activeChatUserIds = await _localDb.getActiveConversationUserIds(currentUid);
      allowedIds.addAll(activeChatUserIds);
    } catch (_) {}

    try {
      final res = await _contactsService.syncContacts();
      final registered = res['registered'] ?? [];
      for (final c in registered) {
        if (c.appUserId != null && c.appUserId!.isNotEmpty && c.appUserId != currentUid) {
          allowedIds.add(c.appUserId!);
        }
      }
    } catch (_) {}

    try {
      final users = await SupabaseConfig.client.from('users').select('id').limit(200);
      for (final u in users) {
        final uid = u['id']?.toString();
        if (uid != null && uid.isNotEmpty && uid != currentUid) {
          allowedIds.add(uid);
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

    // Encrypt content & caption for E2EE storage with AES-256
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

    final statusJson = status.toJson();

    // 1. Save to Supabase messages relay with group_id == 'GLOBAL_STATUSES'
    try {
      await SupabaseConfig.client.from('messages').insert({
        'sender_id': currentUid,
        'recipient_id': 'ALL',
        'group_id': 'GLOBAL_STATUSES',
        'message_type': 'status_story',
        'encrypted_content': jsonEncode(statusJson),
        'created_at': now.toIso8601String(),
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Save to Firestore
    try {
      await docRef.set(statusJson).timeout(const Duration(seconds: 4));
    } catch (_) {}

    return status;
  }

  /// Real-time stream of contact status updates combining Supabase + Firestore
  Stream<List<UserStatusGroup>> getRecentStatusesStream() {
    final currentUid = _auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return Stream.value([]);

    pruneExpiredStatuses();

    final controller = StreamController<List<UserStatusGroup>>.broadcast();
    final Map<String, StatusItem> statusesMap = {};

    void processAndEmit() {
      final now = DateTime.now();
      final validStatuses = <StatusItem>[];

      for (final status in statusesMap.values) {
        if (status.expiresAt.isBefore(now)) continue;
        if (status.userId == currentUid) continue;

        if (status.allowedViewerIds.isEmpty || status.allowedViewerIds.contains(currentUid)) {
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
      }

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

      result.sort((a, b) {
        final aUnread = a.hasUnread(currentUid);
        final bUnread = b.hasUnread(currentUid);
        if (aUnread && !bUnread) return -1;
        if (!aUnread && bUnread) return 1;
        return b.lastUpdatedAt.compareTo(a.lastUpdatedAt);
      });

      if (!controller.isClosed) {
        controller.add(result);
      }
    }

    // 1. Supabase Stream on GLOBAL_STATUSES
    StreamSubscription? supaSub;
    try {
      supaSub = SupabaseConfig.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('group_id', 'GLOBAL_STATUSES')
          .listen((data) {
            for (final row in data) {
              try {
                if (row['message_type'] == 'status_story') {
                  final encrypted = row['encrypted_content'] as String? ?? '';
                  final itemMap = jsonDecode(encrypted) as Map<String, dynamic>;
                  final item = StatusItem.fromJson(itemMap);
                  statusesMap[item.id] = item;
                }
              } catch (_) {}
            }
            processAndEmit();
          }, onError: (_) {});
    } catch (_) {}

    // 2. Firestore Stream
    StreamSubscription? fireSub;
    try {
      fireSub = _firestore.collection('statuses').snapshots().listen((snap) {
        for (final doc in snap.docs) {
          try {
            final item = StatusItem.fromJson(doc.data());
            statusesMap[item.id] = item;
          } catch (_) {}
        }
        processAndEmit();
      }, onError: (_) {});
    } catch (_) {}

    // 3. Initial fetch from Supabase
    SupabaseConfig.client
        .from('messages')
        .select()
        .eq('group_id', 'GLOBAL_STATUSES')
        .eq('message_type', 'status_story')
        .order('created_at', ascending: false)
        .limit(50)
        .then((rows) {
          for (final row in rows) {
            try {
              final encrypted = row['encrypted_content'] as String? ?? '';
              final itemMap = jsonDecode(encrypted) as Map<String, dynamic>;
              final item = StatusItem.fromJson(itemMap);
              statusesMap[item.id] = item;
            } catch (_) {}
          }
          processAndEmit();
        }).catchError((_) {});

    controller.onCancel = () {
      supaSub?.cancel();
      fireSub?.cancel();
    };

    return controller.stream;
  }

  /// Real-time stream of current user's own active statuses
  Stream<List<StatusItem>> getMyStatusesStream() {
    final currentUid = _auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return Stream.value([]);

    final controller = StreamController<List<StatusItem>>.broadcast();
    final Map<String, StatusItem> myStatusesMap = {};

    void processAndEmit() {
      final now = DateTime.now();
      final myStatuses = <StatusItem>[];

      for (final status in myStatusesMap.values) {
        if (status.userId == currentUid && status.expiresAt.isAfter(now)) {
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
      }

      myStatuses.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!controller.isClosed) {
        controller.add(myStatuses);
      }
    }

    // 1. Supabase Stream
    StreamSubscription? supaSub;
    try {
      supaSub = SupabaseConfig.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('group_id', 'GLOBAL_STATUSES')
          .listen((data) {
            for (final row in data) {
              try {
                if (row['message_type'] == 'status_story' && row['sender_id'] == currentUid) {
                  final encrypted = row['encrypted_content'] as String? ?? '';
                  final itemMap = jsonDecode(encrypted) as Map<String, dynamic>;
                  final item = StatusItem.fromJson(itemMap);
                  myStatusesMap[item.id] = item;
                }
              } catch (_) {}
            }
            processAndEmit();
          }, onError: (_) {});
    } catch (_) {}

    // 2. Firestore Stream
    StreamSubscription? fireSub;
    try {
      fireSub = _firestore
          .collection('statuses')
          .where('user_id', isEqualTo: currentUid)
          .snapshots()
          .listen((snap) {
            for (final doc in snap.docs) {
              try {
                final item = StatusItem.fromJson(doc.data());
                myStatusesMap[item.id] = item;
              } catch (_) {}
            }
            processAndEmit();
          }, onError: (_) {});
    } catch (_) {}

    // 3. Initial fetch from Supabase
    SupabaseConfig.client
        .from('messages')
        .select()
        .eq('group_id', 'GLOBAL_STATUSES')
        .eq('sender_id', currentUid)
        .limit(20)
        .then((rows) {
          for (final row in rows) {
            try {
              final encrypted = row['encrypted_content'] as String? ?? '';
              final itemMap = jsonDecode(encrypted) as Map<String, dynamic>;
              final item = StatusItem.fromJson(itemMap);
              myStatusesMap[item.id] = item;
            } catch (_) {}
          }
          processAndEmit();
        }).catchError((_) {});

    controller.onCancel = () {
      supaSub?.cancel();
      fireSub?.cancel();
    };

    return controller.stream;
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
          .from('messages')
          .delete()
          .eq('group_id', 'GLOBAL_STATUSES')
          .lt('created_at', cutoff.toIso8601String());
    } catch (_) {}
  }

  /// Delete status by ID
  Future<void> deleteStatus(String statusId) async {
    try {
      await _firestore.collection('statuses').doc(statusId).delete();
    } catch (_) {}
  }
}
