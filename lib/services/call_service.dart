import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/call_model.dart';
import 'local_database_service.dart';
import 'supabase_config.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Uuid _uuid = const Uuid();

  StreamSubscription? _incomingCallSub;
  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallController.stream;

  /// Start listening for incoming call signals in real-time
  void startIncomingCallListener() {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return;

    _incomingCallSub?.cancel();
    _incomingCallSub = _firestore
        .collection('call_signals')
        .where('receiver_id', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        data['doc_id'] = doc.id;
        _incomingCallController.add(data);
      }
    });
  }

  /// Create and initiate a new outgoing E2EE call
  Future<String> startCall({
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = false,
  }) async {
    final myUid = _auth.currentUser?.uid ?? '';
    final myName = _auth.currentUser?.displayName ?? _auth.currentUser?.phoneNumber ?? 'Usuario';
    final myAvatar = _auth.currentUser?.photoURL;
    final callId = _uuid.v4();

    final callData = {
      'id': callId,
      'caller_id': myUid,
      'caller_name': myName,
      'caller_avatar': myAvatar,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'receiver_avatar': receiverAvatar,
      'status': 'ringing',
      'is_video': isVideo,
      'created_at': DateTime.now().toIso8601String(),
    };

    // 1. Post signal to Firestore with timeout
    try {
      await _firestore.collection('call_signals').doc(callId).set(callData).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Post signal to Supabase
    try {
      await SupabaseConfig.client.from('call_signals').upsert(callData).timeout(const Duration(seconds: 4));
    } catch (_) {}

    return callId;
  }

  /// Listen to call state changes (connected, ended, rejected)
  Stream<DocumentSnapshot<Map<String, dynamic>>> getCallStream(String callId) {
    return _firestore.collection('call_signals').doc(callId).snapshots();
  }

  /// Answer incoming call
  Future<void> answerCall(String callId) async {
    try {
      await _firestore.collection('call_signals').doc(callId).update({'status': 'connected'});
      await SupabaseConfig.client.from('call_signals').update({'status': 'connected'}).eq('id', callId);
    } catch (_) {}
  }

  /// Reject incoming call
  Future<void> rejectCall({
    required String callId,
    required String callerId,
    required String callerName,
    String? callerAvatar,
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = false,
  }) async {
    try {
      await _firestore.collection('call_signals').doc(callId).update({'status': 'rejected'});
      await SupabaseConfig.client.from('call_signals').update({'status': 'rejected'}).eq('id', callId);
    } catch (_) {}

    // Save as missed/rejected in local DB
    final log = CallLog(
      id: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverAvatar: receiverAvatar,
      direction: CallDirection.incoming,
      status: CallStatus.rejected,
      durationSeconds: 0,
      timestamp: DateTime.now(),
      isVideo: isVideo,
    );
    await _localDb.saveCallLog(log);
  }

  /// End / Terminate call and record call duration
  Future<void> endCall({
    required String callId,
    required String callerId,
    required String callerName,
    String? callerAvatar,
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    required CallDirection direction,
    required int durationSeconds,
    bool isVideo = false,
  }) async {
    try {
      await _firestore.collection('call_signals').doc(callId).update({'status': 'ended'});
      await SupabaseConfig.client.from('call_signals').update({'status': 'ended'}).eq('id', callId);
    } catch (_) {}

    final log = CallLog(
      id: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverAvatar: receiverAvatar,
      direction: direction,
      status: durationSeconds > 0 ? CallStatus.completed : (direction == CallDirection.outgoing ? CallStatus.rejected : CallStatus.missed),
      durationSeconds: durationSeconds,
      timestamp: DateTime.now(),
      isVideo: isVideo,
    );
    await _localDb.saveCallLog(log);
  }
}
