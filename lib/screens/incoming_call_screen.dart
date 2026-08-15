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

  late String _resolvedCallerName;
  String? _resolvedCallerAvatar;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _resolvedCallerName = widget.callerName.isNotEmpty && widget.callerName != 'Contacto' && widget.callerName != 'Usuario'
        ? widget.callerName
        : 'Contacto';
    _resolvedCallerAvatar = widget.callerAvatar;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playRingtone();
    _listenToCallStatus();
    _resolveCallerProfile();
  }

  void _resolveCallerProfile() async {
    final profile = await _callService.resolveUserProfile(widget.callerId);
    if (mounted) {
      setState(() {
        if (profile['name'] != null && profile['name'] != 'Contacto' && profile['name'] != 'Usuario') {
          _resolvedCallerName = profile['name']!;
        }
        if (profile['avatar'] != null && profile['avatar']!.isNotEmpty) {
          _resolvedCallerAvatar = profile['avatar'];
        }
      });
    }
  }

  void _playRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource('audio/incoming_ring.wav'));
    } catch (_) {}
  }

  void _listenToCallStatus() {
    _callSignalSub = _callService.getCallStream(widget.callId).listen((data) {
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
            otherUserName: _resolvedCallerName,
            otherUserAvatar: _resolvedCallerAvatar,
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

    final myProf = await _callService.getMyProfile();

    await _callService.rejectCall(
      callId: widget.callId,
      callerId: widget.callerId,
      callerName: _resolvedCallerName,
      callerAvatar: _resolvedCallerAvatar,
      receiverId: _callService.currentUserId,
      receiverName: myProf['name'] ?? 'Usuario',
      receiverAvatar: myProf['avatar'],
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
    final initialLetter = _resolvedCallerName.isNotEmpty && _resolvedCallerName != 'Contacto'
        ? _resolvedCallerName[0].toUpperCase()
        : 'C';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _rejectCall();
      },
      child: Scaffold(
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
                        backgroundImage: (_resolvedCallerAvatar != null && _resolvedCallerAvatar!.isNotEmpty && _resolvedCallerAvatar!.startsWith('http'))
                            ? NetworkImage(_resolvedCallerAvatar!)
                            : null,
                        child: (_resolvedCallerAvatar == null || !_resolvedCallerAvatar!.startsWith('http'))
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
                                    style: const TextStyle(color: Color(0xFFFF1744), fontSize: 44, fontWeight: FontWeight.bold),
                                  ),
                                ),
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
                _resolvedCallerName,
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
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x55E53935),
                                blurRadius: 16,
                                spreadRadius: 2,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Rechazar',
                        style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
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
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x5500E676),
                                blurRadius: 16,
                                spreadRadius: 2,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.call_rounded, color: Colors.black, size: 36),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Contestar',
                        style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
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
    ));
  }
}
