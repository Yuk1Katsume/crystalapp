import 'dart:async';
import 'dart:convert';
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
  CallService._internal() {
    _auth.authStateChanges().listen((user) {
      if (user != null && user.uid.isNotEmpty) {
        startIncomingCallListener();
      }
    });
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final CallNotificationService _notificationService = CallNotificationService();
  final Uuid _uuid = const Uuid();

  StreamSubscription? _firestoreIncomingSub;
  StreamSubscription? _supabaseIncomingSub;
  Timer? _pollingTimer;

  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallController.stream;

  final Set<String> _processedCallIds = {};
  final Set<String> _activeRingingCallIds = {};

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

  /// Start listening for incoming call signals across Supabase Realtime + Firestore
  void startIncomingCallListener() {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return;

    _firestoreIncomingSub?.cancel();
    _supabaseIncomingSub?.cancel();
    _pollingTimer?.cancel();

    // 1. Supabase Real-time messages stream where recipient_id == myUid and message_type == 'call_signal'
    try {
      _supabaseIncomingSub = SupabaseConfig.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', myUid)
          .listen((data) {
            for (final item in data) {
              if (item['message_type'] == 'call_signal') {
                try {
                  final encrypted = item['encrypted_content'] as String? ?? '';
                  final signalData = jsonDecode(encrypted) as Map<String, dynamic>;
                  signalData['message_id'] = item['id'];
                  handleIncomingCallSignal(signalData);

                  // Delete signal from Supabase relay after processing
                  SupabaseConfig.client.from('messages').delete().eq('id', item['id']).then((_) {}).catchError((_) {});
                } catch (_) {}
              }
            }
          }, onError: (_) {});
    } catch (_) {}

    // 2. Firestore Stream
    try {
      _firestoreIncomingSub = _firestore
          .collection('call_signals')
          .where('receiver_id', isEqualTo: myUid)
          .snapshots()
          .listen((snap) {
            for (final doc in snap.docs) {
              final data = doc.data();
              data['doc_id'] = doc.id;
              handleIncomingCallSignal(data);
            }
          }, onError: (_) {});
    } catch (_) {}

    // 3. Fast Periodic Polling (every 3 seconds) for instant sync & missed calls
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollPendingCallSignals();
    });

    _pollPendingCallSignals();
  }

  void handleIncomingCallSignal(Map<String, dynamic> data) async {
    final callId = (data['call_id'] ?? data['id'] ?? data['doc_id'] ?? '').toString();
    if (callId.isEmpty) return;

    final status = (data['status'] ?? 'ringing').toString();
    final callerName = (data['caller_name'] ?? 'Contacto').toString();
    final callerId = (data['caller_id'] ?? '').toString();
    final callerAvatar = data['caller_avatar'] as String?;
    final isVideo = data['is_video'] == true;

    if (status == 'ringing') {
      if (!_activeRingingCallIds.contains(callId)) {
        _activeRingingCallIds.add(callId);

        // Show Heads-Up Notification & Trigger Stream
        await _notificationService.showIncomingCallNotification(
          notificationId: callId.hashCode,
          callerName: callerName,
          isVideo: isVideo,
          callId: callId,
        );

        _incomingCallController.add(data);
      }
    } else if (status == 'ended' || status == 'rejected') {
      if (_activeRingingCallIds.contains(callId)) {
        _activeRingingCallIds.remove(callId);
        await _notificationService.cancelCallNotification(callId.hashCode);

        if (!_processedCallIds.contains(callId)) {
          _processedCallIds.add(callId);
          final log = CallLog(
            id: callId,
            callerId: callerId,
            callerName: callerName,
            callerAvatar: callerAvatar,
            receiverId: currentUserId,
            receiverName: currentUserName,
            receiverAvatar: currentUserAvatar,
            direction: CallDirection.incoming,
            status: CallStatus.missed,
            durationSeconds: 0,
            timestamp: DateTime.now(),
            isVideo: isVideo,
          );
          await _localDb.saveCallLog(log);
        }
      }
    }
  }

  Future<void> _pollPendingCallSignals() async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return;

    try {
      final res = await SupabaseConfig.client
          .from('messages')
          .select()
          .eq('recipient_id', myUid)
          .eq('message_type', 'call_signal')
          .order('created_at', ascending: false)
          .limit(5);

      for (final item in res) {
        try {
          final encrypted = item['encrypted_content'] as String? ?? '';
          final signalData = jsonDecode(encrypted) as Map<String, dynamic>;
          signalData['message_id'] = item['id'];
          handleIncomingCallSignal(signalData);
          SupabaseConfig.client.from('messages').delete().eq('id', item['id']).then((_) {}).catchError((_) {});
        } catch (_) {}
      }
    } catch (_) {}
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
    RTCSessionDescription? offer;
    try {
      await _initWebRTC(isVideo: isVideo, isCaller: true, callId: callId);
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

    final callPayload = {
      'call_id': callId,
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

    // 2. Post signal to Supabase messages relay (INSTANT)
    try {
      await SupabaseConfig.client.from('messages').insert({
        'sender_id': myUid,
        'recipient_id': receiverId,
        'group_id': 'CALL_$callId',
        'message_type': 'call_signal',
        'encrypted_content': jsonEncode(callPayload),
        'created_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 3. Post signal to Firestore
    try {
      await _firestore.collection('call_signals').doc(callId).set(callPayload).timeout(const Duration(seconds: 4));
    } catch (_) {}

    return callId;
  }

  /// Listen to call state changes across both Supabase messages stream and Firestore
  Stream<Map<String, dynamic>> getCallStream(String callId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();

    // Supabase Stream on group_id == 'CALL_$callId'
    final supaSub = SupabaseConfig.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', 'CALL_$callId')
        .listen((data) {
          for (final row in data) {
            try {
              final encrypted = row['encrypted_content'] as String? ?? '';
              final signalData = jsonDecode(encrypted) as Map<String, dynamic>;
              if (!controller.isClosed) {
                controller.add(signalData);
              }
            } catch (_) {}
          }
        }, onError: (_) {});

    // Firestore Stream
    final fireSub = _firestore.collection('call_signals').doc(callId).snapshots().listen((doc) {
      if (doc.exists && !controller.isClosed) {
        final d = doc.data() ?? {};
        d['call_id'] = doc.id;
        controller.add(d);
      }
    }, onError: (_) {});

    controller.onCancel = () {
      supaSub.cancel();
      fireSub.cancel();
    };

    return controller.stream;
  }

  /// Answer incoming call
  Future<void> answerCall(String callId) async {
    _activeRingingCallIds.remove(callId);
    await _notificationService.cancelCallNotification(callId.hashCode);

    try {
      // 1. Fetch Call Doc
      Map<String, dynamic>? data;
      try {
        final res = await SupabaseConfig.client
            .from('messages')
            .select()
            .eq('group_id', 'CALL_$callId')
            .order('created_at', ascending: false)
            .limit(1);
        if (res.isNotEmpty) {
          final enc = res.first['encrypted_content'] as String? ?? '';
          data = jsonDecode(enc) as Map<String, dynamic>;
        }
      } catch (_) {}

      if (data == null) {
        final doc = await _firestore.collection('call_signals').doc(callId).get();
        data = doc.data();
      }

      final isVideo = data?['is_video'] == true;
      final offerMap = data?['sdp_offer'] as Map<String, dynamic>?;
      final callerId = (data?['caller_id'] ?? '').toString();

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

      final answerPayload = {
        'call_id': callId,
        'status': 'connected',
        'sdp_answer': answer?.toMap(),
        'connected_at': DateTime.now().toIso8601String(),
      };

      // 5. Post connected event to Supabase
      if (callerId.isNotEmpty) {
        try {
          await SupabaseConfig.client.from('messages').insert({
            'sender_id': currentUserId,
            'recipient_id': callerId,
            'group_id': 'CALL_$callId',
            'message_type': 'call_signal',
            'encrypted_content': jsonEncode(answerPayload),
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      // 6. Post connected event to Firestore
      try {
        await _firestore.collection('call_signals').doc(callId).set(answerPayload, SetOptions(merge: true));
      } catch (_) {}
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
    _activeRingingCallIds.remove(callId);
    _processedCallIds.add(callId);
    await _notificationService.cancelCallNotification(callId.hashCode);

    final payload = {
      'call_id': callId,
      'status': 'rejected',
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      await SupabaseConfig.client.from('messages').insert({
        'sender_id': currentUserId,
        'recipient_id': callerId,
        'group_id': 'CALL_$callId',
        'message_type': 'call_signal',
        'encrypted_content': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    try {
      await _firestore.collection('call_signals').doc(callId).set(payload, SetOptions(merge: true));
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
    _activeRingingCallIds.remove(callId);
    _processedCallIds.add(callId);
    await _notificationService.cancelCallNotification(callId.hashCode);

    final otherUid = direction == CallDirection.outgoing ? receiverId : callerId;

    final payload = {
      'call_id': callId,
      'status': 'ended',
      'duration': durationSeconds,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      await SupabaseConfig.client.from('messages').insert({
        'sender_id': currentUserId,
        'recipient_id': otherUid,
        'group_id': 'CALL_$callId',
        'message_type': 'call_signal',
        'encrypted_content': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    try {
      await _firestore.collection('call_signals').doc(callId).set(payload, SetOptions(merge: true));
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
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo ? {'facingMode': 'user'} : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _peerConnection = await createPeerConnection(_iceServers);

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        }
      };

      _peerConnection?.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          final candMap = candidate.toMap();
          _firestore
              .collection('call_signals')
              .doc(callId)
              .collection('candidates')
              .add(candMap);
        }
      };

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
