import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import 'chat_service.dart';
import 'e2ee_service.dart';
import 'local_database_service.dart';
import 'supabase_config.dart';
import 'voice_note_service.dart';

class GroupChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  final LocalDatabaseService _localDb = LocalDatabaseService();

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
                if (group.memberIds.isEmpty) {
                  // Group was deleted entirely
                  currentGroupsMap.remove(group.id);
                } else if (currentGroupsMap.containsKey(group.id) || group.memberIds.contains(myUid)) {
                  // Keep group visible even if user was removed so they keep their chat history until they delete it
                  currentGroupsMap[group.id] = group;
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
      final currentUid = _auth.currentUser?.uid ?? '';
      final group = await getGroupDetails(groupId);
      if (group == null) return false;

      final updatedMembers = List<String>.from(group.memberIds)..remove(memberId);

      // If no members remain, delete the group entirely
      if (updatedMembers.isEmpty) {
        _firestore.collection('groups').doc(groupId).delete().timeout(const Duration(seconds: 4)).catchError((_) {});
        SupabaseConfig.client.from('messages').delete().eq('group_id', groupId).catchError((_) {});
        final delMetadata = GroupModel(
          id: group.id,
          name: group.name,
          description: group.description,
          iconUrl: group.iconUrl,
          memberIds: [],
          adminId: '',
          createdAt: group.createdAt,
        );
        SupabaseConfig.client.from('messages').insert({
          'sender_id': currentUid,
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(delMetadata.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4)).catchError((_) {});
        return true;
      }

      // If the admin is leaving or removed, randomly pick another member to be the new admin
      String newAdminId = group.adminId;
      String? newAdminName;
      if (group.adminId == memberId) {
        final listCopy = List<String>.from(updatedMembers)..shuffle();
        newAdminId = listCopy.first;
        try {
          final newAdminRow = await SupabaseConfig.client
              .from('users')
              .select('display_name, username')
              .eq('id', newAdminId)
              .maybeSingle();
          if (newAdminRow != null) {
            newAdminName = newAdminRow['display_name'] ?? newAdminRow['username'];
          }
        } catch (_) {}
      }

      // 1. Update Firestore
      _firestore.collection('groups').doc(groupId).update({
        'memberIds': updatedMembers,
        'adminId': newAdminId,
      }).timeout(const Duration(seconds: 4)).catchError((_) {});

      // 2. Broadcast updated group to Supabase
      final updatedGroup = GroupModel(
        id: group.id,
        name: group.name,
        description: group.description,
        iconUrl: group.iconUrl,
        memberIds: updatedMembers,
        adminId: newAdminId,
        createdAt: group.createdAt,
      );

      try {
        await SupabaseConfig.client.from('messages').insert({
          'sender_id': currentUid,
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(updatedGroup.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // 3. Send system message in chat
      try {
        String actorName = 'Un admin';
        String targetName = 'un usuario';

        final users = await SupabaseConfig.client
            .from('users')
            .select('id, display_name, username')
            .filter('id', 'in', [currentUid, memberId]);

        for (var u in users) {
          final uid = u['id']?.toString();
          final name = u['display_name'] ?? u['username'] ?? 'Usuario';
          if (uid == currentUid) actorName = name;
          if (uid == memberId) targetName = name;
        }

        final isSelfExit = (memberId == currentUid);
        final sysText = jsonEncode({
          'action': isSelfExit ? 'member_left' : 'member_removed',
          'actor_id': currentUid,
          'actor_name': actorName,
          'target_id': memberId,
          'target_name': targetName,
        });

        await sendGroupSystemMessage(groupId: groupId, systemText: sysText);

        // If admin changed, notify the group chat
        if (newAdminId != group.adminId) {
          final adminSysText = jsonEncode({
            'action': 'admin_assigned',
            'actor_id': newAdminId,
            'actor_name': newAdminName ?? 'Un miembro',
          });
          await sendGroupSystemMessage(groupId: groupId, systemText: adminSysText);
        }
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add new members to existing group
  Future<bool> addMembersToGroup(String groupId, List<String> newMemberIds) async {
    try {
      final currentUid = _auth.currentUser?.uid ?? '';
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
          'sender_id': currentUid,
          'recipient_id': 'ALL',
          'group_id': 'GLOBAL_GROUPS',
          'message_type': 'group_metadata',
          'encrypted_content': jsonEncode(updatedGroup.toJson()),
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // 3. Send system message in chat
      try {
        String actorName = 'Un admin';
        final users = await SupabaseConfig.client
            .from('users')
            .select('id, display_name, username')
            .filter('id', 'in', [currentUid, ...newMemberIds]);

        final Map<String, String> nameMap = {};
        for (var u in users) {
          final uid = u['id']?.toString() ?? '';
          final name = u['display_name'] ?? u['username'] ?? 'Usuario';
          nameMap[uid] = name;
          if (uid == currentUid) actorName = name;
        }

        for (final newUid in newMemberIds) {
          final addedName = nameMap[newUid] ?? 'un usuario';
          final sysText = jsonEncode({
            'action': 'member_added',
            'actor_id': currentUid,
            'actor_name': actorName,
            'target_id': newUid,
            'target_name': addedName,
          });
          await sendGroupSystemMessage(groupId: groupId, systemText: sysText);
        }
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
    String? oldIconUrl,
  }) async {
    try {
      final currentUid = _auth.currentUser?.uid ?? '';
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (iconUrl != null) updates['iconUrl'] = iconUrl;

      // 1. Fetch current details or prepare local fallback
      final group = await getGroupDetails(groupId);
      final updatedGroup = GroupModel(
        id: groupId,
        name: name ?? group?.name ?? 'Grupo',
        description: description ?? group?.description,
        iconUrl: iconUrl ?? group?.iconUrl,
        memberIds: group?.memberIds ?? [currentUid],
        adminId: group?.adminId ?? currentUid,
        createdAt: group?.createdAt ?? DateTime.now(),
      );

      // 2. Broadcast immediately to Supabase GLOBAL_GROUPS in parallel
      SupabaseConfig.client.from('messages').insert({
        'sender_id': currentUid,
        'recipient_id': 'ALL',
        'group_id': 'GLOBAL_GROUPS',
        'message_type': 'group_metadata',
        'encrypted_content': jsonEncode(updatedGroup.toJson()),
        'created_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 4)).catchError((_) {});

      // 3. Update Firestore in parallel with timeout
      if (updates.isNotEmpty) {
        _firestore
            .collection('groups')
            .doc(groupId)
            .update(updates)
            .timeout(const Duration(seconds: 4))
            .catchError((_) {});
      }

      // 4. Fetch actor name for system message
      String actorName = 'Un miembro';
      try {
        final uRow = await SupabaseConfig.client
            .from('users')
            .select('display_name, username')
            .eq('id', currentUid)
            .maybeSingle();
        if (uRow != null) {
          actorName = uRow['display_name'] ?? uRow['username'] ?? 'Un miembro';
        }
      } catch (_) {}

      // 5. Send system message in the group chat
      if (iconUrl != null) {
        final sysText = jsonEncode({
          'action': 'group_icon_changed',
          'actor_id': currentUid,
          'actor_name': actorName,
          'old_icon': oldIconUrl ?? '',
          'new_icon': iconUrl,
        });
        await sendGroupSystemMessage(groupId: groupId, systemText: sysText);
      } else if (description != null) {
        final sysText = jsonEncode({
          'action': 'group_description_changed',
          'actor_id': currentUid,
          'actor_name': actorName,
          'description': description,
        });
        await sendGroupSystemMessage(groupId: groupId, systemText: sysText);
      } else if (name != null) {
        final sysText = jsonEncode({
          'action': 'group_name_changed',
          'actor_id': currentUid,
          'actor_name': actorName,
          'name': name,
        });
        await sendGroupSystemMessage(groupId: groupId, systemText: sysText);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Send system message in a group (photo changed, description changed, etc.)
  Future<void> sendGroupSystemMessage({
    required String groupId,
    required String systemText,
  }) async {
    final currentUid = _auth.currentUser?.uid ?? '';
    final now = DateTime.now();
    final msgId = const Uuid().v4();

    // 1. Save locally in SQLite
    await _localDb.saveLocalMessage(
      id: msgId,
      senderId: currentUid,
      recipientId: groupId,
      groupId: groupId,
      text: systemText,
      messageType: 'system',
      createdAt: now,
      isRead: true,
      status: 'sent',
    );

    // 2. Broadcast single row to group stream
    try {
      await SupabaseConfig.client.from('messages').insert({
        'sender_id': currentUid,
        'recipient_id': 'ALL',
        'group_id': groupId,
        'message_type': 'system',
        'encrypted_content': systemText,
        'created_at': now.toIso8601String(),
      });
    } catch (_) {}
  }

  /// Update group name
  Future<bool> updateGroupName(String groupId, String newName) async {
    return updateGroupInfo(groupId: groupId, name: newName);
  }

  /// Update group description
  Future<bool> updateGroupDescription(String groupId, String newDescription) async {
    return updateGroupInfo(groupId: groupId, description: newDescription);
  }

  /// Pick image for group icon
  Future<XFile?> pickImage() async {
    return await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
  }

  /// Upload group icon to Supabase Storage and broadcast to Supabase + Firestore
  Future<String?> uploadGroupIcon(String groupId, File imageFile, {String? oldIconUrl}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.path.split('.').last;
      final fileName = 'group_${groupId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await SupabaseConfig.client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          )
          .timeout(const Duration(seconds: 10));

      final publicUrl = SupabaseConfig.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await updateGroupInfo(
        groupId: groupId,
        iconUrl: publicUrl,
        oldIconUrl: oldIconUrl,
      );

      return publicUrl;
    } catch (e) {
      return null;
    }
  }

  /// Send encrypted group message to all members and group stream
  Future<void> sendGroupMessage({
    required String groupId,
    required String text,
    ChatMessageType type = ChatMessageType.text,
    String? mediaUrl,
    int? audioDurationSeconds,
    List<double>? waveformSamples,
  }) async {
    final currentUid = _auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    final msgId = const Uuid().v4();
    final now = DateTime.now();

    // 1. Get group details to know member IDs
    final group = await getGroupDetails(groupId);
    final memberIds = group?.memberIds ?? [];

    // 2. Prepare payload & E2EE encryption using shared groupId
    String messageType = type.name;
    String encryptedContent;

    final isAudio = type == ChatMessageType.audio ||
        (mediaUrl != null && (mediaUrl.endsWith('.m4a') || mediaUrl.endsWith('.aac')));
    final isImage = type == ChatMessageType.image && mediaUrl != null && !mediaUrl.startsWith('http');

    if (isAudio && mediaUrl != null) {
      messageType = 'audio';
      final file = File(mediaUrl);
      if (await file.exists()) {
        final audioBytes = await file.readAsBytes();
        final encAudio = E2EEService.encryptBytes(audioBytes, groupId);
        final base64Audio = base64Encode(encAudio);
        if (waveformSamples != null && waveformSamples.isNotEmpty) {
          final wfString = waveformSamples.map((e) => e.toStringAsFixed(2)).join(',');
          final encWf = base64Encode(utf8.encode(wfString));
          encryptedContent = 'AUDENC_WF:$encWf:$base64Audio';
        } else {
          encryptedContent = 'AUDENC:$base64Audio';
        }
      } else {
        encryptedContent = E2EEService.encryptPayload(text, groupId);
      }
    } else if (isImage && mediaUrl != null) {
      messageType = 'image';
      final file = File(mediaUrl);
      if (await file.exists()) {
        final imgBytes = await file.readAsBytes();
        final encImg = E2EEService.encryptBytes(imgBytes, groupId);
        final base64Img = base64Encode(encImg);
        encryptedContent = 'IMGENC:$base64Img';
      } else {
        encryptedContent = E2EEService.encryptPayload(text, groupId);
      }
    } else if (type == ChatMessageType.sticker && mediaUrl != null) {
      messageType = 'sticker';
      encryptedContent = E2EEService.encryptPayload(mediaUrl, groupId);
    } else {
      encryptedContent = E2EEService.encryptPayload(text, groupId);
    }

    // 3. Save locally in SQLite for current user
    await _localDb.saveLocalMessage(
      id: msgId,
      senderId: currentUid,
      recipientId: groupId,
      groupId: groupId,
      text: text,
      messageType: messageType,
      mediaUrl: mediaUrl,
      audioDurationSeconds: audioDurationSeconds,
      audioWaveform: waveformSamples?.map((e) => e.toStringAsFixed(2)).join(','),
      createdAt: now,
      isRead: true,
      status: 'sent',
    );

    // 4. Send targeted row to each group member so their incoming listener receives it
    for (final memberId in memberIds) {
      if (memberId == currentUid) continue;
      try {
        await SupabaseConfig.client.from('messages').insert({
          'sender_id': currentUid,
          'recipient_id': memberId,
          'group_id': groupId,
          'message_type': messageType,
          'encrypted_content': encryptedContent,
          'created_at': now.toIso8601String(),
        });
      } catch (_) {}
    }
  }

  /// Stream group messages from local SQLite + real-time Supabase
  Stream<List<Message>> getGroupMessages(String groupId) {
    final controller = StreamController<List<Message>>.broadcast();
    final currentUid = _auth.currentUser?.uid ?? '';

    // 1. Emit local SQLite history immediately
    _localDb.getLocalMessages(groupId).then((localMsgs) {
      if (!controller.isClosed) controller.add(localMsgs);
    });

    // 2. Listen to real-time incoming messages for this group in Supabase
    final subscription = SupabaseConfig.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: true)
        .listen((data) async {
          bool hasNewIncoming = false;

          for (var item in data) {
            final senderId = item['sender_id'];
            if (senderId == currentUid) continue; // Skip own messages

            final msgId = item['id'].toString();
            final encryptedContent = item['encrypted_content'] as String? ?? '';
            final messageType = item['message_type'] ?? 'text';

            if (messageType == 'group_metadata' || messageType == 'call_signal' || messageType == 'call_candidate') {
              continue;
            }

            String decryptedText;
            String? localMediaPath;
            String? embeddedWaveform;

            final isImg = messageType == 'image' || encryptedContent.startsWith('IMGENC:');
            final isAud = messageType == 'audio' || encryptedContent.startsWith('AUDENC_WF:') || encryptedContent.startsWith('AUDENC:');

            if (isImg && encryptedContent.startsWith('IMGENC:')) {
              decryptedText = '📷 Imagen';
              localMediaPath = await ChatService().extractAndSaveEmbeddedImage(encryptedContent, msgId, groupId);
            } else if (isAud && (encryptedContent.startsWith('AUDENC_WF:') || encryptedContent.startsWith('AUDENC:'))) {
              decryptedText = '🎤 Mensaje de voz';
              localMediaPath = await ChatService().extractAndSaveEmbeddedAudio(encryptedContent, msgId, groupId);
              if (encryptedContent.startsWith('AUDENC_WF:')) {
                final parts = encryptedContent.split(':');
                if (parts.length >= 3) {
                  try {
                    embeddedWaveform = utf8.decode(base64Decode(parts[1]));
                  } catch (_) {}
                }
              }
            } else if (messageType == 'sticker') {
              decryptedText = '🎨 Sticker';
              localMediaPath = E2EEService.decryptPayload(encryptedContent, groupId);
            } else {
              decryptedText = E2EEService.decryptPayload(encryptedContent, groupId);
            }

            // Resolve sender name and avatar from Supabase users
            String? senderName;
            String? senderAvatar;
            try {
              final userRow = await SupabaseConfig.client
                  .from('users')
                  .select('display_name, username, avatar_url')
                  .eq('id', senderId)
                  .maybeSingle();
              if (userRow != null) {
                senderName = userRow['display_name'] ?? userRow['username'];
                senderAvatar = userRow['avatar_url'];
              }
            } catch (_) {}

            await _localDb.saveLocalMessage(
              id: msgId,
              senderId: senderId,
              senderName: senderName,
              senderAvatar: senderAvatar,
              recipientId: groupId,
              groupId: groupId,
              text: decryptedText,
              messageType: isAud ? 'audio' : (isImg ? 'image' : messageType),
              mediaUrl: localMediaPath,
              audioWaveform: embeddedWaveform,
              createdAt: DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now(),
              isRead: false,
              status: 'delivered',
            );

            // Delete targeted row if explicitly addressed to current user
            if (item['recipient_id'] == currentUid) {
              try {
                await SupabaseConfig.client.from('messages').delete().eq('id', item['id']);
              } catch (_) {}
            }

            hasNewIncoming = true;
          }

          if (hasNewIncoming) {
            final updatedLocalMsgs = await _localDb.getLocalMessages(groupId);
            if (!controller.isClosed) controller.add(updatedLocalMsgs);
          }
        });

    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }
}
