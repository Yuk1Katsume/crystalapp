import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  StreamSubscription? _supabaseCandSub;
  StreamSubscription? _firestoreCandSub;
  Timer? _pollingTimer;

  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _callEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallController.stream;
  Stream<Map<String, dynamic>> get onCallEvent => _callEventsController.stream;

  final Set<String> _processedCallIds = {};
  final Set<String> _activeRingingCallIds = {};
  final Map<String, Map<String, dynamic>> _cachedCallData = {};

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // WebRTC Session & Candidate Queue
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _queuedIceCandidates = [];
  bool _hasRemoteDescription = false;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  static final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// Asynchronously resolves current logged in user's profile
  Future<Map<String, String?>> getMyProfile() async {
    final uid = currentUserId;
    if (uid.isEmpty) return {'name': 'Usuario', 'avatar': null};

    String? name;
    String? avatar;

    try {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('current_display_name') ?? prefs.getString('current_username');
      avatar = prefs.getString('current_avatar_url');
    } catch (_) {}

    if (name == null || name.isEmpty || avatar == null || avatar.isEmpty) {
      try {
        final res = await SupabaseConfig.client
            .from('users')
            .select('display_name, username, avatar_url')
            .eq('id', uid)
            .maybeSingle();
        if (res != null) {
          final dName = res['display_name']?.toString();
          final uName = res['username']?.toString();
          final av = res['avatar_url']?.toString();
          if (dName != null && dName.isNotEmpty) {
            name = dName;
          } else if (uName != null && uName.isNotEmpty) {
            name = uName;
          }
          if (av != null && av.isNotEmpty) {
            avatar = av;
          }
        }
      } catch (_) {}
    }

    final fallbackPhone = _auth.currentUser?.phoneNumber ?? 'Usuario';
    return {
      'name': (name != null && name.isNotEmpty) ? name : fallbackPhone,
      'avatar': avatar,
    };
  }

  /// Asynchronously resolves any user's profile by UID
  Future<Map<String, String?>> resolveUserProfile(String uid) async {
    if (uid.isEmpty) return {'name': 'Contacto', 'avatar': null};

    try {
      final res = await SupabaseConfig.client
          .from('users')
          .select('display_name, username, avatar_url')
          .eq('id', uid)
          .maybeSingle();

      if (res != null) {
        final dName = res['display_name']?.toString();
        final uName = res['username']?.toString();
        final avatar = res['avatar_url']?.toString();
        final bestName = (dName != null && dName.isNotEmpty)
            ? dName
            : ((uName != null && uName.isNotEmpty) ? uName : 'Contacto');
        return {'name': bestName, 'avatar': avatar};
      }
    } catch (_) {}

    return {'name': 'Contacto', 'avatar': null};
  }

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
                  if (signalData['status'] == 'ended' || signalData['status'] == 'rejected') {
                    SupabaseConfig.client.from('messages').delete().eq('id', item['id']).then((_) {}).catchError((_) {});
                  }
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

    // Cache call payload in memory
    _cachedCallData[callId] = data;

    final status = (data['status'] ?? 'ringing').toString();
    var callerName = (data['caller_name'] ?? '').toString();
    final callerId = (data['caller_id'] ?? '').toString();
    var callerAvatar = data['caller_avatar'] as String?;
    final isVideo = data['is_video'] == true;

    // Dispatch event to active CallScreen listeners
    _callEventsController.add(data);

    // Resolve profile if callerName is generic or avatar is missing
    if (callerName.isEmpty || callerName == 'Usuario' || callerName == 'Contacto' || callerAvatar == null) {
      final profile = await resolveUserProfile(callerId);
      if (profile['name'] != null && profile['name'] != 'Contacto') {
        callerName = profile['name']!;
      }
      if (profile['avatar'] != null) {
        callerAvatar = profile['avatar'];
      }
      data['caller_name'] = callerName.isNotEmpty ? callerName : 'Contacto';
      data['caller_avatar'] = callerAvatar;
    }

    if (status == 'ringing') {
      if (!_activeRingingCallIds.contains(callId)) {
        _activeRingingCallIds.add(callId);

        // Show Heads-Up Notification & Trigger Stream
        await _notificationService.showIncomingCallNotification(
          notificationId: callId.hashCode,
          callerName: callerName.isNotEmpty ? callerName : 'Contacto',
          isVideo: isVideo,
          callId: callId,
        );

        _incomingCallController.add(data);
      }
    } else if (status == 'connected') {
      // If caller receives answer SDP
      final sdpAnswer = data['sdp_answer'] as Map<String, dynamic>?;
      if (sdpAnswer != null && _peerConnection != null) {
        try {
          final answer = RTCSessionDescription(sdpAnswer['sdp'], sdpAnswer['type']);
          await _peerConnection?.setRemoteDescription(answer);
          await _flushQueuedIceCandidates();
        } catch (_) {}
      }
    } else if (status == 'ended' || status == 'rejected') {
      if (_activeRingingCallIds.contains(callId)) {
        _activeRingingCallIds.remove(callId);
        await _notificationService.cancelCallNotification(callId.hashCode);

        if (!_processedCallIds.contains(callId)) {
          _processedCallIds.add(callId);
          final myProf = await getMyProfile();
          final log = CallLog(
            id: callId,
            callerId: callerId,
            callerName: callerName.isNotEmpty ? callerName : 'Contacto',
            callerAvatar: callerAvatar,
            receiverId: currentUserId,
            receiverName: myProf['name'] ?? 'Usuario',
            receiverAvatar: myProf['avatar'],
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
          if (signalData['status'] == 'ended' || signalData['status'] == 'rejected') {
            SupabaseConfig.client.from('messages').delete().eq('id', item['id']).then((_) {}).catchError((_) {});
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Create and initiate a new outgoing call asynchronously using a pre-generated callId (Zero UI latency)
  Future<void> startCallWithId({
    required String callId,
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = false,
  }) async {
    final myUid = currentUserId;
    final myProfile = await getMyProfile();
    final myName = myProfile['name'] ?? 'Usuario';
    final myAvatar = myProfile['avatar'];

    var finalReceiverName = receiverName;
    var finalReceiverAvatar = receiverAvatar;

    _queuedIceCandidates.clear();
    _hasRemoteDescription = false;

    // 1. Initialize WebRTC Media & Peer Connection
    RTCSessionDescription? offer;
    try {
      await _initWebRTC(isVideo: isVideo, isCaller: true, callId: callId, otherUid: receiverId);
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
      'receiver_name': finalReceiverName,
      'receiver_avatar': finalReceiverAvatar,
      'status': 'ringing',
      'is_video': isVideo,
      'sdp_offer': offer?.toMap(),
      'created_at': DateTime.now().toIso8601String(),
    };

    _cachedCallData[callId] = callPayload;

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
  }

  /// Create and initiate a new outgoing E2EE call with WebRTC
  Future<String> startCall({
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isVideo = false,
  }) async {
    final callId = _uuid.v4();
    await startCallWithId(
      callId: callId,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverAvatar: receiverAvatar,
      isVideo: isVideo,
    );
    return callId;
  }

  /// Listen to call state changes across Supabase, Firestore, and internal call events
  Stream<Map<String, dynamic>> getCallStream(String callId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();

    // 1. Internal fast event bus
    final eventSub = _callEventsController.stream.listen((data) {
      final id = (data['call_id'] ?? data['id'] ?? data['doc_id'] ?? '').toString();
      if (id == callId && !controller.isClosed) {
        controller.add(data);
      }
    });

    // 2. Supabase Stream on group_id == 'CALL_$callId'
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

    // 3. Firestore Stream
    final fireSub = _firestore.collection('call_signals').doc(callId).snapshots().listen((doc) {
      if (doc.exists && !controller.isClosed) {
        final d = doc.data() ?? {};
        d['call_id'] = doc.id;
        controller.add(d);
      }
    }, onError: (_) {});

    controller.onCancel = () {
      eventSub.cancel();
      supaSub.cancel();
      fireSub.cancel();
    };

    return controller.stream;
  }

  /// Answer incoming call with memory cache fallback
  Future<void> answerCall(String callId, {String? callerId, Map<String, dynamic>? sdpOffer}) async {
    _activeRingingCallIds.remove(callId);
    await _notificationService.cancelCallNotification(callId.hashCode);

    _queuedIceCandidates.clear();
    _hasRemoteDescription = false;

    try {
      final cached = _cachedCallData[callId];

      final effectiveCallerId = (callerId != null && callerId.isNotEmpty)
          ? callerId
          : (cached?['caller_id'] ?? '').toString();

      var effectiveOfferMap = sdpOffer ?? (cached?['sdp_offer'] as Map<String, dynamic>?);
      final isVideo = cached?['is_video'] == true;

      // 1. Fallback fetch from Supabase if not in memory
      if (effectiveOfferMap == null) {
        try {
          final res = await SupabaseConfig.client
              .from('messages')
              .select()
              .eq('group_id', 'CALL_$callId')
              .order('created_at', ascending: false)
              .limit(1);
          if (res.isNotEmpty) {
            final enc = res.first['encrypted_content'] as String? ?? '';
            final data = jsonDecode(enc) as Map<String, dynamic>;
            effectiveOfferMap ??= data['sdp_offer'] as Map<String, dynamic>?;
          }
        } catch (_) {}
      }

      // 2. Fallback fetch from Firestore
      if (effectiveOfferMap == null) {
        final doc = await _firestore.collection('call_signals').doc(callId).get();
        effectiveOfferMap = doc.data()?['sdp_offer'] as Map<String, dynamic>?;
      }

      // 3. Initialize WebRTC
      await _initWebRTC(isVideo: isVideo, isCaller: false, callId: callId, otherUid: effectiveCallerId);

      // 4. Set Remote Description
      if (effectiveOfferMap != null) {
        final offer = RTCSessionDescription(effectiveOfferMap['sdp'], effectiveOfferMap['type']);
        await _peerConnection?.setRemoteDescription(offer);
        await _flushQueuedIceCandidates();
      }

      // 5. Create Answer SDP
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

      _cachedCallData[callId] = answerPayload;

      // 6. Post connected event to Supabase
      if (effectiveCallerId.isNotEmpty) {
        try {
          await SupabaseConfig.client.from('messages').insert({
            'sender_id': currentUserId,
            'recipient_id': effectiveCallerId,
            'group_id': 'CALL_$callId',
            'message_type': 'call_signal',
            'encrypted_content': jsonEncode(answerPayload),
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      // 7. Post connected event to Firestore
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

    final pCaller = await resolveUserProfile(callerId);
    final pReceiver = await getMyProfile();

    final log = CallLog(
      id: callId,
      callerId: callerId,
      callerName: (callerName.isNotEmpty && callerName != 'Contacto') ? callerName : (pCaller['name'] ?? 'Contacto'),
      callerAvatar: callerAvatar ?? pCaller['avatar'],
      receiverId: receiverId,
      receiverName: (receiverName.isNotEmpty && receiverName != 'Usuario') ? receiverName : (pReceiver['name'] ?? 'Usuario'),
      receiverAvatar: receiverAvatar ?? pReceiver['avatar'],
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

    var finalCallerName = callerName;
    var finalCallerAvatar = callerAvatar;
    var finalReceiverName = receiverName;
    var finalReceiverAvatar = receiverAvatar;

    if (finalCallerName.isEmpty || finalCallerName == 'Contacto' || finalCallerName == 'Usuario') {
      final cProf = await resolveUserProfile(callerId);
      finalCallerName = cProf['name'] ?? 'Contacto';
      finalCallerAvatar ??= cProf['avatar'];
    }

    if (finalReceiverName.isEmpty || finalReceiverName == 'Contacto' || finalReceiverName == 'Usuario') {
      final rProf = await resolveUserProfile(receiverId);
      finalReceiverName = rProf['name'] ?? 'Contacto';
      finalReceiverAvatar ??= rProf['avatar'];
    }

    final log = CallLog(
      id: callId,
      callerId: callerId,
      callerName: finalCallerName,
      callerAvatar: finalCallerAvatar,
      receiverId: receiverId,
      receiverName: finalReceiverName,
      receiverAvatar: finalReceiverAvatar,
      direction: direction,
      status: durationSeconds > 0 ? CallStatus.completed : CallStatus.missed,
      durationSeconds: durationSeconds,
      timestamp: DateTime.now(),
      isVideo: isVideo,
    );

    await _localDb.saveCallLog(log);
  }

  Future<void> _addIceCandidateSafe(RTCIceCandidate candidate) async {
    if (_peerConnection != null && _hasRemoteDescription) {
      try {
        await _peerConnection?.addCandidate(candidate);
      } catch (_) {}
    } else {
      _queuedIceCandidates.add(candidate);
    }
  }

  Future<void> _flushQueuedIceCandidates() async {
    _hasRemoteDescription = true;
    for (final cand in _queuedIceCandidates) {
      try {
        await _peerConnection?.addCandidate(cand);
      } catch (_) {}
    }
    _queuedIceCandidates.clear();
  }

  /// Initialize WebRTC Peer Connection & Media Streams with Dual Relay Candidate Exchange
  Future<void> _initWebRTC({
    required bool isVideo,
    required bool isCaller,
    required String callId,
    required String otherUid,
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

      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = true;
      });

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteStream?.getAudioTracks().forEach((track) {
            track.enabled = true;
          });
        }
      };

      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}

      _peerConnection?.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _callEventsController.add({'call_id': callId, 'status': 'connected'});
        }
      };

      _peerConnection?.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          _callEventsController.add({'call_id': callId, 'status': 'connected'});
        }
      };

      _peerConnection?.onIceCandidate = (candidate) async {
        if (candidate.candidate != null) {
          final candMap = candidate.toMap();

          // 1. Send candidate via Supabase messages relay
          if (otherUid.isNotEmpty) {
            try {
              await SupabaseConfig.client.from('messages').insert({
                'sender_id': currentUserId,
                'recipient_id': otherUid,
                'group_id': 'CALL_${callId}_CAND',
                'message_type': 'call_candidate',
                'encrypted_content': jsonEncode(candMap),
                'created_at': DateTime.now().toIso8601String(),
              });
            } catch (_) {}
          }

          // 2. Send candidate via Firestore
          try {
            await _firestore
                .collection('call_signals')
                .doc(callId)
                .collection('candidates')
                .add(candMap);
          } catch (_) {}
        }
      };

      // Listen for ICE Candidates via Supabase
      _supabaseCandSub?.cancel();
      _supabaseCandSub = SupabaseConfig.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('group_id', 'CALL_${callId}_CAND')
          .listen((data) {
            for (final row in data) {
              if (row['sender_id'] != currentUserId) {
                try {
                  final candData = jsonDecode(row['encrypted_content'] as String) as Map<String, dynamic>;
                  final cand = RTCIceCandidate(
                    candData['candidate'],
                    candData['sdpMid'],
                    candData['sdpMLineIndex'],
                  );
                  _addIceCandidateSafe(cand);
                  SupabaseConfig.client.from('messages').delete().eq('id', row['id']).then((_) {}).catchError((_) {});
                } catch (_) {}
              }
            }
          }, onError: (_) {});

      // Listen for ICE Candidates via Firestore
      _firestoreCandSub?.cancel();
      _firestoreCandSub = _firestore
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
              _addIceCandidateSafe(cand);
            }
          }
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  void _cleanupWebRTC() {
    try {
      _supabaseCandSub?.cancel();
      _firestoreCandSub?.cancel();

      _queuedIceCandidates.clear();
      _hasRemoteDescription = false;

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
