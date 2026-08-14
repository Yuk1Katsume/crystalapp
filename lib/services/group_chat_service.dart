import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/message_model.dart';
import 'e2ee_service.dart';

class GroupChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final E2EEService _e2eeService = E2EEService();
  final ImagePicker _picker = ImagePicker();

  /// Create a new group chat
  Future<GroupModel?> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    final allMembers = {...memberIds, currentUser.uid}.toList();
    final docRef = _firestore.collection('groups').doc();

    final group = GroupModel(
      id: docRef.id,
      name: name,
      memberIds: allMembers,
      adminId: currentUser.uid,
      createdAt: DateTime.now(),
    );

    await docRef.set(group.toJson());
    return group;
  }

  /// Stream of user groups
  Stream<List<GroupModel>> get myGroups {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => GroupModel.fromJson(doc.data())).toList());
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
    );

    await docRef.set(message.toJson());
  }

  /// Pick Image for Chat/Group
  Future<XFile?> pickImage() async {
    return await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
  }
}
