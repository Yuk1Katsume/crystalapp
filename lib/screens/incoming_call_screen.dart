import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/call_service.dart';
import '../services/call_notification_service.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    this.isVideo = false,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  StreamSubscription? _callSignalSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playRingtone();
    _listenToCallStatus();
  }

  void _playRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource('audio/incoming_ring.wav'));
    } catch (_) {}
  }

  void _listenToCallStatus() {
    _callSignalSub = _callService.getCallStream(widget.callId).listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final status = data['status'] as String?;

      if (status == 'ended' || status == 'rejected') {
        _cleanupAndClose();
      }
    });
  }

  void _cleanupAndClose() {
    _ringtonePlayer.stop();
    CallNotificationService().cancelCallNotification(widget.callId.hashCode);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _answerCall() async {
    await _ringtonePlayer.stop();
    await CallNotificationService().cancelCallNotification(widget.callId.hashCode);
    await _callService.answerCall(widget.callId);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            callId: widget.callId,
            otherUserId: widget.callerId,
            otherUserName: widget.callerName,
            otherUserAvatar: widget.callerAvatar,
            isOutgoing: false,
            isVideo: widget.isVideo,
          ),
        ),
      );
    }
  }

  Future<void> _rejectCall() async {
    await _ringtonePlayer.stop();
    await CallNotificationService().cancelCallNotification(widget.callId.hashCode);

    await _callService.rejectCall(
      callId: widget.callId,
      callerId: widget.callerId,
      callerName: widget.callerName,
      callerAvatar: widget.callerAvatar,
      receiverId: _callService.currentUserId,
      receiverName: _callService.currentUserName,
      receiverAvatar: _callService.currentUserAvatar,
      isVideo: widget.isVideo,
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ringtonePlayer.dispose();
    _callSignalSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Title and Call Type
              Text(
                widget.isVideo ? 'Llamada de Video Entrante' : 'Llamada de Voz Entrante',
                style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock_rounded, size: 14, color: Color(0xFFFF1744)),
                  SizedBox(width: 6),
                  Text(
                    'Cifrado Extremo a Extremo (E2EE)',
                    style: TextStyle(color: Color(0xFFFF8DA1), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              const Spacer(),

              // Animated Pulsing Avatar
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnim.value,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF1744).withOpacity(0.35),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: const Color(0xFF1E1E1E),
                        backgroundImage: (widget.callerAvatar != null && widget.callerAvatar!.startsWith('http'))
                            ? NetworkImage(widget.callerAvatar!)
                            : null,
                        child: (widget.callerAvatar == null || !widget.callerAvatar!.startsWith('http'))
                            ? Text(
                                widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '🌸',
                                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // Caller Name
              Text(
                widget.callerName,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),
              const Text(
                'Llamando a tu dispositivo...',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),

              const Spacer(),

              // Action Buttons: Reject (Red) & Accept (Green)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _rejectCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE53935),
                            boxShadow: [
                              BoxShadow(color: Color(0x66E53935), blurRadius: 20, spreadRadius: 2),
                            ],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Rechazar',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),

                  // Accept Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _answerCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF00C853),
                            boxShadow: [
                              BoxShadow(color: Color(0x6600C853), blurRadius: 20, spreadRadius: 2),
                            ],
                          ),
                          child: const Icon(Icons.call_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Aceptar',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
