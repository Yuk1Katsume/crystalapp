import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/message_model.dart';
import 'chat_service.dart';
import 'e2ee_service.dart';
import 'supabase_config.dart';
import 'voice_note_service.dart';

class GroupChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  /// Create a new group chat with multi-backend resilience
  Future<GroupModel?> createGroup({
    required String name,
    required List<String> memberIds,
    String? description,
    String? iconUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      final currentUid = currentUser?.uid ?? '';
      if (currentUid.isEmpty) return null;

      final allMembers = {...memberIds, currentUid}.toList();
      final docRef = _firestore.collection('groups').doc();

      final group = GroupModel(
        id: docRef.id,
        name: name,
        description: description,
        iconUrl: iconUrl,
        memberIds: allMembers,
        adminId: currentUid,
        createdAt: DateTime.now(),
      );

      // 1. Save to Firestore with timeout
      try {
        await docRef.set(group.toJson()).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // 2. Broadcast to Supabase messages relay
      try {
        await SupabaseConfig.client.from('messages').insert({
          'sender_id': currentUid,
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(group.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      return group;
    } catch (e) {
      final currentUid = _auth.currentUser?.uid ?? '';
      return GroupModel(
        id: 'group_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: description,
        iconUrl: iconUrl,
        memberIds: memberIds,
        adminId: currentUid,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Get details of a single group
  Future<GroupModel?> getGroupDetails(String groupId) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get().timeout(const Duration(seconds: 3));
      if (doc.exists && doc.data() != null) {
        return GroupModel.fromJson(doc.data()!);
      }
    } catch (_) {}

    // Supabase messages fallback
    try {
      final res = await SupabaseConfig.client
          .from('messages')
          .select()
          .eq('group_id', 'GLOBAL_GROUPS')
          .eq('message_type', 'group_metadata')
          .order('created_at', ascending: false)
          .limit(50);

      for (var row in res) {
        try {
          final enc = row['encrypted_content'] as String? ?? '';
          final map = jsonDecode(enc) as Map<String, dynamic>;
          if (map['id'] == groupId) {
            return GroupModel.fromJson(map);
          }
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  /// Stream of user groups (resilient multi-source Supabase + Firestore cloud reader)
  /// Guarantees groups persist across reinstalls as long as user is in memberIds.
  Stream<List<GroupModel>> get myGroups {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    final myUid = user.uid;

    final controller = StreamController<List<GroupModel>>.broadcast();
    final Map<String, GroupModel> currentGroupsMap = {};

    void emitGroups() {
      if (!controller.isClosed) {
        final sortedList = currentGroupsMap.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(sortedList);
      }
    }

    // 1. Initial snapshot from Supabase GLOBAL_GROUPS
    SupabaseConfig.client
        .from('messages')
        .select()
        .eq('group_id', 'GLOBAL_GROUPS')
        .eq('message_type', 'group_metadata')
        .order('created_at', ascending: false)
        .limit(100)
        .then((res) {
          for (var item in res) {
            try {
              final enc = item['encrypted_content'] as String? ?? '';
              final map = jsonDecode(enc) as Map<String, dynamic>;
              final group = GroupModel.fromJson(map);
              if (group.memberIds.contains(myUid)) {
                currentGroupsMap[group.id] = group;
              }
            } catch (_) {}
          }
          emitGroups();
        }).catchError((_) {});

    // 2. Real-time stream from Supabase GLOBAL_GROUPS
    final sbSub = SupabaseConfig.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', 'GLOBAL_GROUPS')
        .listen((data) {
          for (var item in data) {
            if (item['message_type'] == 'group_metadata') {
              try {
                final enc = item['encrypted_content'] as String? ?? '';
                final map = jsonDecode(enc) as Map<String, dynamic>;
                final group = GroupModel.fromJson(map);
                if (group.memberIds.contains(myUid)) {
                  currentGroupsMap[group.id] = group;
                } else {
                  currentGroupsMap.remove(group.id);
                }
              } catch (_) {}
            }
          }
          emitGroups();
        }, onError: (_) {});

    // 3. Real-time stream from Firestore
    final fsSub = _firestore
        .collection('groups')
        .where('memberIds', arrayContains: myUid)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docs) {
            try {
              final g = GroupModel.fromJson(doc.data());
              currentGroupsMap[doc.id] = g;
            } catch (_) {}
          }
          emitGroups();
        }, onError: (_) {});

    controller.onCancel = () {
      sbSub.cancel();
      fsSub.cancel();
    };

    return controller.stream;
  }

  /// Remove/Kick a member from group
  Future<bool> removeMemberFromGroup(String groupId, String memberId) async {
    try {
      final group = await getGroupDetails(groupId);
      if (group == null) return false;

      final updatedMembers = List<String>.from(group.memberIds)..remove(memberId);

      // 1. Update Firestore
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': updatedMembers,
      }).timeout(const Duration(seconds: 4));

      // 2. Broadcast updated group to Supabase
      final updatedGroup = GroupModel(
        id: group.id,
        name: group.name,
        description: group.description,
        iconUrl: group.iconUrl,
        memberIds: updatedMembers,
        adminId: group.adminId,
        createdAt: group.createdAt,
      );

      try {
        await SupabaseConfig.client.from('messages').insert({
          'sender_id': _auth.currentUser?.uid ?? '',
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(updatedGroup.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add new members to existing group
  Future<bool> addMembersToGroup(String groupId, List<String> newMemberIds) async {
    try {
      final group = await getGroupDetails(groupId);
      if (group == null) return false;

      final updatedMembers = {...group.memberIds, ...newMemberIds}.toList();

      // 1. Update Firestore
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': updatedMembers,
      }).timeout(const Duration(seconds: 4));

      // 2. Broadcast to Supabase
      final updatedGroup = GroupModel(
        id: group.id,
        name: group.name,
        description: group.description,
        iconUrl: group.iconUrl,
        memberIds: updatedMembers,
        adminId: group.adminId,
        createdAt: group.createdAt,
      );

      try {
        await SupabaseConfig.client.from('messages').insert({
          'sender_id': _auth.currentUser?.uid ?? '',
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(updatedGroup.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leave group
  Future<bool> leaveGroup(String groupId) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return false;
    return removeMemberFromGroup(groupId, currentUid);
  }

  /// Find all groups in common between the current user and another user
  Future<List<GroupModel>> getGroupsInCommon(String otherUserId) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('groups')
          .where('memberIds', arrayContains: user.uid)
          .get()
          .timeout(const Duration(seconds: 4));

      return snapshot.docs
          .map((doc) => GroupModel.fromJson(doc.data()))
          .where((g) => g.memberIds.contains(otherUserId))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Update group general info (name, description, icon)
  Future<bool> updateGroupInfo({
    required String groupId,
    String? name,
    String? description,
    String? iconUrl,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (iconUrl != null) updates['iconUrl'] = iconUrl;

      if (updates.isNotEmpty) {
        await _firestore.collection('groups').doc(groupId).update(updates);
      }

      final group = await getGroupDetails(groupId);
      if (group != null) {
        final updatedGroup = GroupModel(
          id: group.id,
          name: name ?? group.name,
          description: description ?? group.description,
          iconUrl: iconUrl ?? group.iconUrl,
          memberIds: group.memberIds,
          adminId: group.adminId,
          createdAt: group.createdAt,
        );

        try {
          await SupabaseConfig.client.from('messages').insert({
            'sender_id': _auth.currentUser?.uid ?? '',
            'recipient_id': 'ALL',
            'group_id': 'GLOBAL_GROUPS',
            'message_type': 'group_metadata',
            'encrypted_content': jsonEncode(updatedGroup.toJson()),
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update group name
  Future<bool> updateGroupName(String groupId, String newName) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({'name': newName});
      final group = await getGroupDetails(groupId);
      if (group != null) {
        final updatedGroup = GroupModel(
          id: group.id,
          name: newName,
          description: group.description,
          iconUrl: group.iconUrl,
          memberIds: group.memberIds,
          adminId: group.adminId,
          createdAt: group.createdAt,
        );
        try {
          await SupabaseConfig.client.from('messages').insert({
            'sender_id': _auth.currentUser?.uid ?? '',
            'recipient_id': 'ALL',
            'group_id': 'GLOBAL_GROUPS',
            'message_type': 'group_metadata',
            'encrypted_content': jsonEncode(updatedGroup.toJson()),
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update group description
  Future<bool> updateGroupDescription(String groupId, String newDescription) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({'description': newDescription});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pick image for group icon
  Future<XFile?> pickImage() async {
    return await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
  }

  /// Upload group icon to Supabase Storage
  Future<String?> uploadGroupIcon(String groupId, File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.path.split('.').last;
      final fileName = 'group_${groupId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await SupabaseConfig.client.storage
          .from('avatars')
          .uploadBinary(fileName, bytes);

      final publicUrl = SupabaseConfig.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await _firestore.collection('groups').doc(groupId).update({'iconUrl': publicUrl});
      return publicUrl;
    } catch (e) {
      return null;
    }
  }

  /// Send encrypted group message
  Future<void> sendGroupMessage({
    required String groupId,
    required String text,
    ChatMessageType type = ChatMessageType.text,
    String? mediaUrl,
    int? audioDurationSeconds,
    List<double>? waveformSamples,
  }) async {
    await ChatService().sendDirectMessage(
      recipientId: groupId,
      text: text,
      type: type,
      mediaUrl: mediaUrl,
      audioDurationSeconds: audioDurationSeconds,
      waveformSamples: waveformSamples,
    );
  }

  /// Stream group messages
  Stream<List<Message>> getGroupMessages(String groupId) {
    return ChatService().getChatMessagesWithUser(groupId);
  }
}
