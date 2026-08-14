import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';

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
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String _currentName = FirebaseAuth.instance.currentUser?.displayName ?? 'Usuario';
  final String? _currentAvatar = FirebaseAuth.instance.currentUser?.photoURL;

  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeaker = false;
  int _callDuration = 0;
  Timer? _callTimer;
  StreamSubscription? _callStreamSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _listenToCallSignals();
  }

  void _listenToCallSignals() {
    _callStreamSub = _callService.getCallStream(widget.callId).listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final status = data['status'] as String?;

      if (status == 'connected' && !_isConnected) {
        setState(() {
          _isConnected = true;
        });
        _startTimer();
      } else if (status == 'ended' || status == 'rejected') {
        _onCallEndedByRemote();
      }
    });

    // Auto connect after 2 seconds for demo/direct P2P call simulation if outgoing
    if (widget.isOutgoing) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isConnected) {
          _callService.answerCall(widget.callId);
        }
      });
    }
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

  void _onCallEndedByRemote() {
    _callTimer?.cancel();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Llamada finalizada'),
          backgroundColor: Color(0xFF1E1E1E),
        ),
      );
    }
  }

  Future<void> _hangup() async {
    _callTimer?.cancel();
    await _callService.endCall(
      callId: widget.callId,
      callerId: widget.isOutgoing ? _currentUid : widget.otherUserId,
      callerName: widget.isOutgoing ? _currentName : widget.otherUserName,
      callerAvatar: widget.isOutgoing ? _currentAvatar : widget.otherUserAvatar,
      receiverId: widget.isOutgoing ? widget.otherUserId : _currentUid,
      receiverName: widget.isOutgoing ? widget.otherUserName : _currentName,
      receiverAvatar: widget.isOutgoing ? widget.otherUserAvatar : _currentAvatar,
      direction: widget.isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
      durationSeconds: _callDuration,
      isVideo: widget.isVideo,
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _callStreamSub?.cancel();
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
        : (widget.isOutgoing ? 'Llamando...' : 'Llamada entrante...');

    return Scaffold(
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
                            color: const Color(0xFFFF1744).withOpacity(_isConnected ? 0.3 : 0.6),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: const Color(0xFF1E1E1E),
                        backgroundImage: (widget.otherUserAvatar != null && widget.otherUserAvatar!.isNotEmpty)
                            ? NetworkImage(widget.otherUserAvatar!)
                            : null,
                        child: (widget.otherUserAvatar == null || widget.otherUserAvatar!.isEmpty)
                            ? Text(
                                widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '🌸',
                                style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
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
              widget.otherUserName,
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
                    onTap: () {
                      setState(() => _isMuted = !_isMuted);
                    },
                  ),

                  // End Call (Hang up)
                  GestureDetector(
                    onTap: _hangup,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x66E53935), blurRadius: 18, spreadRadius: 2),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                  ),

                  // Speaker
                  _buildActionButton(
                    icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: 'Altavoz',
                    isActive: _isSpeaker,
                    onTap: () {
                      setState(() => _isSpeaker = !_isSpeaker);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : const Color(0xFF1E1E1E),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
