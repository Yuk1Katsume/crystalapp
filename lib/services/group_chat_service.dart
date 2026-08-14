import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/message_model.dart';
import 'e2ee_service.dart';
import 'supabase_config.dart';
import 'voice_note_service.dart';

class GroupChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final E2EEService _e2eeService = E2EEService();
  final ImagePicker _picker = ImagePicker();

  /// Create a new group chat with timeout and multi-backend resilience
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

      // Save to Firestore with timeout
      try {
        await docRef.set(group.toJson()).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // Also persist to Supabase groups table
      try {
        await SupabaseConfig.client.from('groups').upsert({
          'id': group.id,
          'name': group.name,
          'description': group.description,
          'icon_url': group.iconUrl,
          'member_ids': group.memberIds,
          'admin_id': group.adminId,
          'created_at': group.createdAt.toIso8601String(),
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

    // Supabase fallback
    try {
      final res = await SupabaseConfig.client.from('groups').select().eq('id', groupId).maybeSingle().timeout(const Duration(seconds: 3));
      if (res != null) {
        return GroupModel(
          id: res['id'],
          name: res['name'] ?? 'Grupo',
          description: res['description'],
          iconUrl: res['icon_url'],
          memberIds: List<String>.from(res['member_ids'] ?? []),
          adminId: res['admin_id'] ?? '',
          createdAt: DateTime.tryParse(res['created_at'] ?? '') ?? DateTime.now(),
        );
      }
    } catch (_) {}

    return null;
  }

  /// Stream of user groups (resilient multi-source Supabase + Firestore real-time)
  Stream<List<GroupModel>> get myGroups {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    final myUid = user.uid;

    final controller = StreamController<List<GroupModel>>();
    final Map<String, GroupModel> currentGroupsMap = {};

    void emitGroups() {
      if (!controller.isClosed) {
        final sortedList = currentGroupsMap.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(sortedList);
      }
    }

    // 1. Initial snapshot from Supabase
    SupabaseConfig.client.from('groups').select().then((res) {
      for (var item in res) {
        final members = List<String>.from(item['member_ids'] ?? item['memberIds'] ?? []);
        if (members.contains(myUid)) {
          currentGroupsMap[item['id']] = GroupModel(
            id: item['id'],
            name: item['name'] ?? 'Grupo',
            description: item['description'],
            iconUrl: item['icon_url'] ?? item['iconUrl'],
            memberIds: members,
            adminId: item['admin_id'] ?? item['adminId'] ?? '',
            createdAt: DateTime.tryParse(item['created_at'] ?? item['createdAt'] ?? '') ?? DateTime.now(),
          );
        }
      }
      emitGroups();
    }).catchError((_) {});

    // 2. Real-time stream from Supabase groups table
    final sbSub = SupabaseConfig.client
        .from('groups')
        .stream(primaryKey: ['id'])
        .listen((data) {
          final Set<String> currentIdsInStream = {};
          for (var item in data) {
            final members = List<String>.from(item['member_ids'] ?? item['memberIds'] ?? []);
            final id = item['id'] as String;
            currentIdsInStream.add(id);

            if (members.contains(myUid)) {
              currentGroupsMap[id] = GroupModel(
                id: id,
                name: item['name'] ?? 'Grupo',
                description: item['description'],
                iconUrl: item['icon_url'] ?? item['iconUrl'],
                memberIds: members,
                adminId: item['admin_id'] ?? item['adminId'] ?? '',
                createdAt: DateTime.tryParse(item['created_at'] ?? item['createdAt'] ?? '') ?? DateTime.now(),
              );
            } else {
              currentGroupsMap.remove(id);
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
            currentGroupsMap[doc.id] = GroupModel.fromJson(doc.data());
          }
          emitGroups();
        }, onError: (_) {});

    controller.onCancel = () {
      sbSub.cancel();
      fsSub.cancel();
    };

    return controller.stream;
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
          .where((group) => group.memberIds.contains(otherUserId))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Update group name, description, or icon
  Future<void> updateGroupInfo({
    required String groupId,
    String? name,
    String? description,
    String? iconUrl,
  }) async {
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (iconUrl != null) updates['iconUrl'] = iconUrl;

    try {
      await _firestore.collection('groups').doc(groupId).update(updates).timeout(const Duration(seconds: 4));
    } catch (_) {}

    try {
      final Map<String, dynamic> sbUpdates = {};
      if (name != null) sbUpdates['name'] = name;
      if (description != null) sbUpdates['description'] = description;
      if (iconUrl != null) sbUpdates['icon_url'] = iconUrl;
      await SupabaseConfig.client.from('groups').update(sbUpdates).eq('id', groupId).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Upload new group icon and update group
  Future<String?> uploadGroupIcon(String groupId, File imageFile) async {
    try {
      final ext = imageFile.path.split('.').last;
      final fileName = 'group_${groupId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage.from('avatars').upload(fileName, imageFile);
      final publicUrl = SupabaseConfig.client.storage.from('avatars').getPublicUrl(fileName);

      await updateGroupInfo(groupId: groupId, iconUrl: publicUrl);
      return publicUrl;
    } catch (e) {
      return null;
    }
  }

  /// Add new members to group across Firestore and Supabase
  Future<void> addMembersToGroup(String groupId, List<String> newMemberIds) async {
    // 1. Firestore
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': FieldValue.arrayUnion(newMemberIds),
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Supabase
    try {
      final res = await SupabaseConfig.client
          .from('groups')
          .select('member_ids')
          .eq('id', groupId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      
      final currentList = List<String>.from(res?['member_ids'] ?? []);
      final updatedList = {...currentList, ...newMemberIds}.toList();
      
      await SupabaseConfig.client
          .from('groups')
          .update({'member_ids': updatedList})
          .eq('id', groupId)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Remove a member or leave group across Firestore and Supabase
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {
    // 1. Firestore
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([memberId]),
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Supabase
    try {
      final res = await SupabaseConfig.client
          .from('groups')
          .select('member_ids')
          .eq('id', groupId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      
      final currentList = List<String>.from(res?['member_ids'] ?? []);
      currentList.remove(memberId);
      
      await SupabaseConfig.client
          .from('groups')
          .update({'member_ids': currentList})
          .eq('id', groupId)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Stream of group messages (E2EE decrypted)
  Stream<List<Message>> getGroupMessages(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .asyncMap((snapshot) async {
      List<Message> messages = [];
      for (var doc in snapshot.docs) {
        final msg = Message.fromJson(doc.data());
        if (msg.isEncrypted) {
          final decryptedText =
              E2EEService.decryptPayload(msg.text, groupId + '_group_key');
          messages.add(Message(
            id: msg.id,
            text: decryptedText,
            timestamp: msg.timestamp,
            senderId: msg.senderId,
            senderName: msg.senderName,
            groupId: msg.groupId,
            isEncrypted: true,
            type: msg.type,
            mediaUrl: msg.mediaUrl,
            audioDurationSeconds: msg.audioDurationSeconds,
            isRead: msg.isRead,
          ));
        } else {
          messages.add(msg);
        }
      }
      return messages;
    });
  }

  /// Send message to group (E2EE encrypted)
  Future<void> sendGroupMessage({
    required String groupId,
    required String text,
    ChatMessageType type = ChatMessageType.text,
    String? mediaUrl,
    int? audioDurationSeconds,
    List<double>? waveformSamples,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final encryptedText =
        E2EEService.encryptPayload(text, groupId + '_group_key');

    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc();

    List<double>? samples = waveformSamples;
    if (samples == null && mediaUrl != null && VoiceNoteService.messageWaveforms.containsKey(mediaUrl)) {
      samples = VoiceNoteService.messageWaveforms[mediaUrl];
    }
    final waveformStr = samples?.map((s) => s.toStringAsFixed(2)).join(',');

    if (samples != null) {
      VoiceNoteService.cacheWaveform(docRef.id, samples);
      if (mediaUrl != null) {
        VoiceNoteService.cacheWaveform(mediaUrl, samples);
      }
    }

    final message = Message(
      id: docRef.id,
      text: encryptedText,
      timestamp: DateTime.now(),
      senderId: user.uid,
      senderName: user.displayName ?? user.phoneNumber ?? 'Member',
      groupId: groupId,
      isEncrypted: true,
      type: type,
      mediaUrl: mediaUrl,
      audioDurationSeconds: audioDurationSeconds,
      audioWaveform: waveformStr,
    );

    try {
      await docRef.set(message.toJson()).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Pick Image for Chat/Group
  Future<XFile?> pickImage() async {
    return await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
  }
}
