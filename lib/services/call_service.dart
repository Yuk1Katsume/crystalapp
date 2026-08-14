import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../models/call_model.dart';
import 'local_database_service.dart';
import 'supabase_config.dart';
import 'call_notification_service.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final CallNotificationService _notificationService = CallNotificationService();
  final Uuid _uuid = const Uuid();

  StreamSubscription? _incomingCallSub;
  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallController.stream;

  String get currentUserId => _auth.currentUser?.uid ?? '';
  String get currentUserName =>
      _auth.currentUser?.displayName ?? _auth.currentUser?.phoneNumber ?? 'Usuario';
  String? get currentUserAvatar => _auth.currentUser?.photoURL;

  // WebRTC Session
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  static final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

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
        final callId = data['id'] ?? doc.id;
        final callerName = data['caller_name'] ?? 'Contacto';
        final isVideo = data['is_video'] ?? false;

        // Show Heads-Up Notification & Trigger Stream
        _notificationService.showIncomingCallNotification(
          notificationId: callId.hashCode,
          callerName: callerName,
          isVideo: isVideo,
          callId: callId,
        );

        _incomingCallController.add(data);
      }
    });
  }

  /// Create and initiate a new outgoing E2EE call with WebRTC
  Future<String> startCall({
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = false,
  }) async {
    final myUid = currentUserId;
    final myName = currentUserName;
    final myAvatar = currentUserAvatar;
    final callId = _uuid.v4();

    // 1. Initialize WebRTC Media & Peer Connection
    await _initWebRTC(isVideo: isVideo, isCaller: true, callId: callId);

    // 2. Create Offer SDP
    RTCSessionDescription? offer;
    try {
      offer = await _peerConnection?.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': isVideo,
        },
        'optional': [],
      });
      if (offer != null) {
        await _peerConnection?.setLocalDescription(offer);
      }
    } catch (_) {}

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
      'sdp_offer': offer?.toMap(),
      'created_at': DateTime.now().toIso8601String(),
    };

    // 3. Post signal to Firestore
    try {
      await _firestore.collection('call_signals').doc(callId).set(callData).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 4. Post signal to Supabase
    try {
      await SupabaseConfig.client.from('call_signals').upsert({
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
      }).timeout(const Duration(seconds: 4));
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
      // 1. Fetch Call Doc to get Offer SDP
      final doc = await _firestore.collection('call_signals').doc(callId).get();
      final data = doc.data() ?? {};
      final isVideo = data['is_video'] ?? false;
      final offerMap = data['sdp_offer'] as Map<String, dynamic>?;

      // 2. Initialize WebRTC
      await _initWebRTC(isVideo: isVideo, isCaller: false, callId: callId);

      // 3. Set Remote Description
      if (offerMap != null) {
        final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
        await _peerConnection?.setRemoteDescription(offer);
      }

      // 4. Create Answer SDP
      final answer = await _peerConnection?.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': isVideo,
        },
        'optional': [],
      });

      if (answer != null) {
        await _peerConnection?.setLocalDescription(answer);
      }

      // 5. Update Call status to connected
      final updateData = {
        'status': 'connected',
        'sdp_answer': answer?.toMap(),
        'connected_at': DateTime.now().toIso8601String(),
      };

      await _firestore.collection('call_signals').doc(callId).update(updateData);
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

    _cleanupWebRTC();

    // Save as rejected in local SQLite DB
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

    _cleanupWebRTC();

    final log = CallLog(
      id: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverAvatar: receiverAvatar,
      direction: direction,
      status: durationSeconds > 0 ? CallStatus.completed : CallStatus.missed,
      durationSeconds: durationSeconds,
      timestamp: DateTime.now(),
      isVideo: isVideo,
    );

    await _localDb.saveCallLog(log);
  }

  /// Initialize WebRTC Peer Connection & Media Streams
  Future<void> _initWebRTC({
    required bool isVideo,
    required bool isCaller,
    required String callId,
  }) async {
    try {
      // 1. Get User Media (Audio / Video)
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo ? {'facingMode': 'user'} : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // 2. Create Peer Connection
      _peerConnection = await createPeerConnection(_iceServers);

      // 3. Add Local Tracks to Peer Connection
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      // 4. Handle Remote Stream
      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        }
      };

      // 5. ICE Candidate Exchange
      _peerConnection?.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          final candMap = candidate.toMap();
          final candidateDoc = isCaller ? 'caller_candidate' : 'receiver_candidate';
          _firestore
              .collection('call_signals')
              .doc(callId)
              .collection('candidates')
              .add(candMap);
        }
      };

      // Listen for remote ICE Candidates
      _firestore
          .collection('call_signals')
          .doc(callId)
          .collection('candidates')
          .snapshots()
          .listen((snap) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null) {
              final cand = RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );
              _peerConnection?.addCandidate(cand);
            }
          }
        }
      });
    } catch (_) {}
  }

  void _cleanupWebRTC() {
    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;

      _remoteStream?.dispose();
      _remoteStream = null;

      _peerConnection?.close();
      _peerConnection?.dispose();
      _peerConnection = null;
    } catch (_) {}
  }
}
