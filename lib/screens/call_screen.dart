import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';
import '../services/call_notification_service.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool isOutgoing;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.callId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.isOutgoing,
    this.isVideo = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final AudioPlayer _soundPlayer = AudioPlayer();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late String _resolvedUserName;
  String? _resolvedUserAvatar;

  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isEnding = false;
  int _callDuration = 0;
  Timer? _callTimer;
  StreamSubscription? _callStreamSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _resolvedUserName = widget.otherUserName.isNotEmpty && widget.otherUserName != 'Contacto' && widget.otherUserName != 'Usuario'
        ? widget.otherUserName
        : 'Contacto';
    _resolvedUserAvatar = widget.otherUserAvatar;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // If incoming call was answered, the call is ALREADY connected!
    if (!widget.isOutgoing) {
      _isConnected = true;
      _startTimer();
    } else {
      _playOutgoingDialToneIfOutgoing();
      // Start call asynchronously in background with zero UI delay
      _callService.startCallWithId(
        callId: widget.callId,
        receiverId: widget.otherUserId,
        receiverName: widget.otherUserName,
        receiverAvatar: widget.otherUserAvatar,
        isVideo: widget.isVideo,
      );
    }

    _listenToCallSignals();
    _resolveProfile();
  }

  void _resolveProfile() async {
    final profile = await _callService.resolveUserProfile(widget.otherUserId);
    if (mounted) {
      setState(() {
        if (profile['name'] != null && profile['name'] != 'Contacto' && profile['name'] != 'Usuario') {
          _resolvedUserName = profile['name']!;
        }
        if (profile['avatar'] != null && profile['avatar']!.isNotEmpty) {
          _resolvedUserAvatar = profile['avatar'];
        }
      });
    }
  }

  void _playOutgoingDialToneIfOutgoing() async {
    if (widget.isOutgoing) {
      try {
        await _soundPlayer.setReleaseMode(ReleaseMode.loop);
        await _soundPlayer.play(AssetSource('audio/dial_tone.wav'));
      } catch (_) {}
    }
  }

  void _listenToCallSignals() {
    _callStreamSub = _callService.getCallStream(widget.callId).listen((data) async {
      final status = data['status'] as String?;

      if (status == 'connected' && !_isConnected) {
        await _soundPlayer.stop();
        if (mounted) {
          setState(() {
            _isConnected = true;
          });
          _startTimer();
        }
      } else if (status == 'ended' || status == 'rejected') {
        _onCallEndedByRemote();
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  void _onCallEndedByRemote() async {
    if (_isEnding) return;
    _isEnding = true;

    _callTimer?.cancel();
    _callStreamSub?.cancel();
    await _soundPlayer.stop();
    try {
      await _soundPlayer.play(AssetSource('audio/call_ended.wav'));
    } catch (_) {}

    await CallNotificationService().cancelCallNotification(widget.callId.hashCode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Llamada finalizada 📞'),
          backgroundColor: Color(0xFF1E1E1E),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _hangup() async {
    if (_isEnding) return;
    _isEnding = true;

    _callTimer?.cancel();
    _callStreamSub?.cancel();
    await _soundPlayer.stop();
    try {
      await _soundPlayer.play(AssetSource('audio/call_ended.wav'));
    } catch (_) {}

    await CallNotificationService().cancelCallNotification(widget.callId.hashCode);

    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    final myProf = await _callService.getMyProfile();

    _callService.endCall(
      callId: widget.callId,
      callerId: widget.isOutgoing ? _currentUid : widget.otherUserId,
      callerName: widget.isOutgoing ? (myProf['name'] ?? 'Usuario') : _resolvedUserName,
      callerAvatar: widget.isOutgoing ? myProf['avatar'] : _resolvedUserAvatar,
      receiverId: widget.isOutgoing ? widget.otherUserId : _currentUid,
      receiverName: widget.isOutgoing ? _resolvedUserName : (myProf['name'] ?? 'Usuario'),
      receiverAvatar: widget.isOutgoing ? _resolvedUserAvatar : myProf['avatar'],
      direction: widget.isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
      durationSeconds: _callDuration,
      isVideo: widget.isVideo,
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    try {
      _callService.localStream?.getAudioTracks().forEach((track) {
        track.enabled = !_isMuted;
      });
    } catch (_) {}
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    try {
      Helper.setSpeakerphoneOn(_isSpeaker);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _callStreamSub?.cancel();
    _soundPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isConnected
        ? _formatDuration(_callDuration)
        : (widget.isOutgoing ? 'Llamando...' : 'Conectando audio E2EE...');

    final initialLetter = _resolvedUserName.isNotEmpty && _resolvedUserName != 'Contacto'
        ? _resolvedUserName[0].toUpperCase()
        : 'U';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _hangup();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Column(
          children: [
            const SizedBox(height: 24),

            // E2EE Lock Banner
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock_rounded, color: Color(0xFFFF1744), size: 14),
                SizedBox(width: 6),
                Text(
                  'Cifrado de extremo a extremo',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Other User Avatar with Pulsing Halo
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isConnected ? 1.0 : _pulseAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF1744).withOpacity(_isConnected ? 0.25 : 0.6),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: const Color(0xFF1E1E1E),
                        backgroundImage: (_resolvedUserAvatar != null && _resolvedUserAvatar!.isNotEmpty && _resolvedUserAvatar!.startsWith('http'))
                            ? NetworkImage(_resolvedUserAvatar!)
                            : null,
                        child: (_resolvedUserAvatar == null || !_resolvedUserAvatar!.startsWith('http'))
                            ? Container(
                                width: 130,
                                height: 130,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF2A2A2A), Color(0xFF141414)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    initialLetter,
                                    style: const TextStyle(color: Color(0xFFFF1744), fontSize: 48, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 28),

            // User Name
            Text(
              _resolvedUserName,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            // Status or Live Timer
            Text(
              statusText,
              style: TextStyle(
                color: _isConnected ? const Color(0xFFFF1744) : Colors.white60,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            // Call Action Buttons (Mute, Speaker, Hangup)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute Microphone
                  _buildActionButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Silenciado' : 'Silenciar',
                    isActive: _isMuted,
                    onTap: _toggleMute,
                  ),

                  // Hangup Button (Red)
                  GestureDetector(
                    onTap: _hangup,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66E53935),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                    ),
                  ),

                  // Speakerphone
                  _buildActionButton(
                    icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: _isSpeaker ? 'Altavoz ON' : 'Altavoz',
                    isActive: _isSpeaker,
                    onTap: _toggleSpeaker,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ));
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : const Color(0xFF1E1E1E),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? Colors.transparent : Colors.white12,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF0A0A0A) : Colors.white70,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
