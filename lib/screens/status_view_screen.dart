import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/status_model.dart';
import '../services/status_service.dart';
import '../services/chat_service.dart';

class StatusViewScreen extends StatefulWidget {
  final UserStatusGroup statusGroup;

  const StatusViewScreen({super.key, required this.statusGroup});

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  int _currentIndex = 0;
  final StatusService _statusService = StatusService();
  final ChatService _chatService = ChatService();
  final TextEditingController _replyController = TextEditingController();
  final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _loadCurrentStory();
  }

  void _loadCurrentStory() {
    _animController.stop();
    _animController.reset();
    _animController.forward();

    final story = widget.statusGroup.statuses[_currentIndex];
    _statusService.markStatusAsViewed(story.id);
  }

  void _nextStory() {
    if (_currentIndex < widget.statusGroup.statuses.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadCurrentStory();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadCurrentStory();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    final story = widget.statusGroup.statuses[_currentIndex];
    final replyMessage = '🌸 Respondió a tu estado: "$text"';

    await _chatService.sendDirectMessage(
      recipientId: widget.statusGroup.userId,
      text: replyMessage,
    );

    _replyController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respuesta enviada ✉️'), backgroundColor: Color(0xFF1E1E1E)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.statusGroup.statuses[_currentIndex];
    final totalStories = widget.statusGroup.statuses.length;

    Color parsedBgColor = const Color(0xFF1E1E1E);
    if (story.backgroundColor.startsWith('#')) {
      try {
        final hex = story.backgroundColor.replaceAll('#', '');
        parsedBgColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < screenWidth / 3) {
              _prevStory();
            } else {
              _nextStory();
            }
          },
          onLongPressStart: (_) => _animController.stop(),
          onLongPressEnd: (_) => _animController.forward(),
          child: Stack(
            children: [
              // Story Content
              Positioned.fill(
                child: _buildStoryContent(story, parsedBgColor),
              ),

              // Top Progress Bars (WhatsApp / Instagram style)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Row(
                  children: List.generate(totalStories, (index) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            double fill = 0.0;
                            if (index < _currentIndex) {
                              fill = 1.0;
                            } else if (index == _currentIndex) {
                              fill = _animController.value;
                            }
                            return FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: fill,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Header (Avatar, Name, Time, Close)
              Positioned(
                top: 22,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF262626),
                      backgroundImage: (widget.statusGroup.userAvatarUrl != null &&
                              widget.statusGroup.userAvatarUrl!.isNotEmpty)
                          ? NetworkImage(widget.statusGroup.userAvatarUrl!)
                          : null,
                      child: (widget.statusGroup.userAvatarUrl == null ||
                              widget.statusGroup.userAvatarUrl!.isEmpty)
                          ? Text(
                              widget.statusGroup.userName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.statusGroup.userName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          _formatTime(story.createdAt),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Caption (if any)
              if (story.caption != null && story.caption!.isNotEmpty)
                Positioned(
                  bottom: 74,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      story.caption!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),

              // Bottom Reply Bar (if viewing another contact's status)
              if (widget.statusGroup.userId != currentUserId)
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: TextField(
                            controller: _replyController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Responder a ${widget.statusGroup.userName}...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        backgroundColor: const Color(0xFFFF1744),
                        elevation: 2,
                        shape: const CircleBorder(),
                        onPressed: _sendReply,
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoryContent(StatusItem story, Color bgColor) {
    if (story.type == 'text') {
      return Container(
        color: bgColor,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          story.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
          ),
        ),
      );
    } else if (story.type == 'image') {
      // Decode Base64 or show Image
      try {
        if (story.content.startsWith('http')) {
          return Image.network(story.content, fit: BoxFit.contain);
        } else {
          final imageBytes = base64Decode(story.content);
          return Image.memory(imageBytes, fit: BoxFit.contain);
        }
      } catch (_) {
        return const Center(
          child: Text('🔒 Error al decodificar imagen', style: TextStyle(color: Colors.white54)),
        );
      }
    } else if (story.type == 'audio') {
      return Container(
        color: const Color(0xFF0F0F0F),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF1744), width: 2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF1744).withOpacity(0.3), blurRadius: 24, spreadRadius: 4),
                ],
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFFFF1744), size: 64),
            ),
            const SizedBox(height: 24),
            Text(
              'Nota de voz de ${widget.statusGroup.userName}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '🔒 Audio cifrado de extremo a extremo',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    } else if (story.type == 'video') {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.play_circle_filled_rounded, color: Color(0xFFFF1744), size: 80),
            SizedBox(height: 16),
            Text('Video Cifrado E2EE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Reproduciendo historia...', style: TextStyle(color: Colors.white60, fontSize: 13)),
          ],
        ),
      );
    } else {
      return Container(
        color: const Color(0xFF121212),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.lock_outline_rounded, color: Color(0xFFFF1744), size: 48),
            SizedBox(height: 12),
            Text('Estado Cifrado E2EE', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      );
    }
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      return 'Hace ${diff.inHours} h';
    } else {
      return 'Ayer';
    }
  }
}
