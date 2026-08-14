import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/voice_note_service.dart';

class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final String sharedKey;
  final String? senderAvatarUrl;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.sharedKey,
    this.senderAvatarUrl,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final VoiceNoteService _voiceService = VoiceNoteService();
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _localDecryptedPath;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  StreamSubscription? _posSub;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _playingMsgSub;

  // 36 simulated waveform bar heights based on message ID hash for organic look
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    final seed = widget.message.id.hashCode;
    _barHeights = List.generate(34, (i) {
      final val = (((seed + i * 37) % 100) / 100.0);
      return 6.0 + (val * 18.0);
    });

    if (widget.message.audioDurationSeconds != null && widget.message.audioDurationSeconds! > 0) {
      _totalDuration = Duration(seconds: widget.message.audioDurationSeconds!);
    }

    _playingMsgSub = _voiceService.playingMessageController.stream.listen((activeId) {
      if (activeId != widget.message.id && _isPlaying && mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    });

    _posSub = _voiceService.globalChatPlayer.onPositionChanged.listen((pos) {
      if (_voiceService.currentlyPlayingMessageId == widget.message.id && mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });

    _playerStateSub = _voiceService.globalChatPlayer.onPlayerComplete.listen((_) {
      if (_voiceService.currentlyPlayingMessageId == widget.message.id && mounted) {
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playerStateSub?.cancel();
    _playingMsgSub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _togglePlay() async {
    if (widget.message.mediaUrl == null) return;

    if (_isPlaying) {
      await _voiceService.pauseMessageAudio();
      setState(() => _isPlaying = false);
      return;
    }

    if (_localDecryptedPath == null) {
      setState(() => _isLoading = true);
      final decrypted = await _voiceService.resolveAndDecryptAudio(
        rawMediaUrl: widget.message.mediaUrl!,
        sharedKey: widget.sharedKey,
        messageId: widget.message.id,
      );
      if (mounted) {
        setState(() {
          _localDecryptedPath = decrypted;
          _isLoading = false;
        });
      }
    }

    if (_localDecryptedPath != null && mounted) {
      setState(() => _isPlaying = true);
      await _voiceService.playMessageAudio(
        messageId: widget.message.id,
        audioPath: _localDecryptedPath!,
      );
    }
  }

  void _seek(double relativeProgress) {
    if (_totalDuration.inMilliseconds > 0 && _voiceService.currentlyPlayingMessageId == widget.message.id) {
      final targetMs = (relativeProgress * _totalDuration.inMilliseconds).round();
      _voiceService.globalChatPlayer.seek(Duration(milliseconds: targetMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = '${widget.message.timestamp.hour.toString().padLeft(2, '0')}:${widget.message.timestamp.minute.toString().padLeft(2, '0')}';
    final isMe = widget.isMe;

    final progress = _totalDuration.inMilliseconds > 0
        ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final bubbleBg = isMe
        ? const Color(0xFFB52355) // Pink magenta matching reference image 1
        : const Color(0xFF1E2428); // Dark bubble for incoming

    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 6),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with overlapping Microphone Badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF121212),
                    backgroundImage: (widget.senderAvatarUrl != null && widget.senderAvatarUrl!.startsWith('http'))
                        ? NetworkImage(widget.senderAvatarUrl!)
                        : null,
                    child: (widget.senderAvatarUrl == null || !widget.senderAvatarUrl!.startsWith('http'))
                        ? Text(
                            (widget.message.senderName != null && widget.message.senderName!.isNotEmpty)
                                ? widget.message.senderName![0].toUpperCase()
                                : (isMe ? 'T' : '?'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF121212),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 8),

              // Play / Pause Button
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: _isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                ),
              ),

              const SizedBox(width: 4),

              // Waveform Track with Scrubber
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final rel = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        _seek(rel);
                      },
                      onTapDown: (details) {
                        final rel = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        _seek(rel);
                      },
                      child: SizedBox(
                        height: 28,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // Waveform Bars
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(_barHeights.length, (i) {
                                final barProg = i / (_barHeights.length - 1);
                                final isPassed = barProg <= progress;
                                return Container(
                                  width: 2.8,
                                  height: _barHeights[i],
                                  decoration: BoxDecoration(
                                    color: isPassed ? Colors.white : Colors.white38,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                            ),

                            // White / Pink Scrubber Dot thumb
                            Positioned(
                              left: ((constraints.maxWidth - 12) * progress).clamp(0.0, constraints.maxWidth - 12),
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.white : const Color(0xFFFF2E74),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // Bottom Row: Duration | Timestamp + Checks
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 4, top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_isPlaying ? _currentPosition : _totalDuration),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: Color(0xFF00E5FF), // Cyan double checkmarks matching reference
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
