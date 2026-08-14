import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/voice_note_service.dart';

enum RecordingMode {
  holding,
  locked,
  paused,
}

class VoiceRecordingBar extends StatefulWidget {
  final RecordingMode initialMode;
  final VoidCallback onCancel;
  final Function(String audioPath, int durationSeconds, [List<double>? waveformSamples]) onSend;

  const VoiceRecordingBar({
    super.key,
    this.initialMode = RecordingMode.holding,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<VoiceRecordingBar> createState() => _VoiceRecordingBarState();
}

class _VoiceRecordingBarState extends State<VoiceRecordingBar> with SingleTickerProviderStateMixin {
  final VoiceNoteService _voiceService = VoiceNoteService();
  late RecordingMode _mode;

  int _duration = 0;
  StreamSubscription<int>? _durationSub;
  StreamSubscription<double>? _ampSub;

  double _dragOffsetX = 0.0;
  double _dragOffsetY = 0.0;

  // Waveform heights for animated equalizer in locked mode
  final List<double> _liveAmplitudes = List.generate(24, (_) => 0.15);

  // Preview state
  bool _isPreviewPlaying = false;
  Duration _previewPosition = Duration.zero;
  Duration _previewTotalDuration = Duration.zero;
  StreamSubscription? _previewPosSub;
  StreamSubscription? _previewCompleteSub;
  String? _stoppedAudioPath;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _durationSub = _voiceService.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _ampSub = _voiceService.amplitudeStream.listen((amp) {
      if (mounted && _mode == RecordingMode.locked) {
        setState(() {
          _liveAmplitudes.removeAt(0);
          _liveAmplitudes.add(amp.clamp(0.1, 1.0));
        });
      }
    });

    _previewPosSub = _voiceService.previewPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _previewPosition = pos);
    });

    _previewCompleteSub = _voiceService.previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
          _previewPosition = Duration.zero;
        });
      }
    });

    if (_mode == RecordingMode.holding) {
      _startInitialRecording();
    }
  }

  void _startInitialRecording() async {
    HapticFeedback.mediumImpact();
    final ok = await _voiceService.startRecording();
    if (!ok && mounted) {
      widget.onCancel();
    }
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _ampSub?.cancel();
    _previewPosSub?.cancel();
    _previewCompleteSub?.cancel();
    _pulseController.dispose();
    _voiceService.stopPreview();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString();
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handleLock() {
    HapticFeedback.heavyImpact();
    setState(() {
      _mode = RecordingMode.locked;
      _dragOffsetX = 0;
      _dragOffsetY = 0;
    });
  }

  List<double> _previewWaveformSamples = List.generate(32, (_) => 0.15);

  void _handlePause() async {
    HapticFeedback.lightImpact();
    await _voiceService.pauseRecording();
    setState(() {
      _mode = RecordingMode.paused;
    });
  }

  void _handleResume() async {
    HapticFeedback.lightImpact();
    await _voiceService.stopPreview();
    setState(() => _isPreviewPlaying = false);
    await _voiceService.resumeRecording();
    setState(() {
      _mode = RecordingMode.locked;
    });
  }

  void _handleTrash() async {
    HapticFeedback.mediumImpact();
    await _voiceService.cancelRecording();
    widget.onCancel();
  }

  void _handleSend() async {
    HapticFeedback.mediumImpact();
    await _voiceService.stopPreview();
    final result = await _voiceService.stopRecording();
    if (result != null && result['path'] != null) {
      final samples = result['samples'] as List<double>?;
      widget.onSend(result['path'], result['duration'] ?? _duration, samples);
    } else if (_stoppedAudioPath != null) {
      widget.onSend(_stoppedAudioPath!, _duration > 0 ? _duration : 1, _previewWaveformSamples);
    } else {
      widget.onCancel();
    }
  }

  void _togglePreviewPlay() async {
    if (_stoppedAudioPath == null) {
      final res = await _voiceService.stopRecording();
      if (res != null) {
        _stoppedAudioPath = res['path'];
        _previewTotalDuration = Duration(seconds: res['duration'] ?? _duration);
        if (res['samples'] != null) {
          _previewWaveformSamples = (res['samples'] as List<double>);
        } else if (_stoppedAudioPath != null) {
          _previewWaveformSamples = await VoiceNoteService.extractWaveformFromAudioFile(_stoppedAudioPath!, barCount: 32);
        }
      }
    }

    if (_stoppedAudioPath == null) return;

    if (_isPreviewPlaying) {
      await _voiceService.stopPreview();
      setState(() => _isPreviewPlaying = false);
    } else {
      await _voiceService.startPreview(_stoppedAudioPath!);
      setState(() => _isPreviewPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _mode == RecordingMode.holding
            ? _buildHoldingView()
            : (_mode == RecordingMode.locked ? _buildLockedView() : _buildPausedPreviewView()),
      ),
    );
  }

  // --- STATE 1: HOLD TO RECORD ---
  Widget _buildHoldingView() {
    final cancelTranslate = (_dragOffsetX < 0 ? _dragOffsetX : 0.0).clamp(-120.0, 0.0);
    final opacityCancel = (1.0 - (cancelTranslate.abs() / 120.0)).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Lock Indicator Capsule above microphone
        Positioned(
          right: 8,
          bottom: 70,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2428),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: Colors.white70, size: 20),
                SizedBox(height: 4),
                Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),

        // Bottom Bar
        Container(
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2428),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              // Red pulsing recording mic + timer
              ScaleTransition(
                scale: _pulseAnimation,
                child: const Icon(Icons.mic_rounded, color: Color(0xFFFF1744), size: 22),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),

              const Spacer(),

              // Slide to cancel hint
              Opacity(
                opacity: opacityCancel,
                child: Transform.translate(
                  offset: Offset(cancelTranslate, 0),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 20),
                      SizedBox(width: 4),
                      Text(
                        'Desliza para cancelar',
                        style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 18),

              // Mic Button
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _dragOffsetX += details.delta.dx;
                    _dragOffsetY += details.delta.dy;
                  });

                  if (_dragOffsetX < -80) {
                    _handleTrash();
                  } else if (_dragOffsetY < -55) {
                    _handleLock();
                  }
                },
                onPanEnd: (_) {
                  if (_mode == RecordingMode.holding) {
                    _handleSend();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF2E74),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- STATE 2: LOCKED HANDS-FREE RECORDING ---
  Widget _buildLockedView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF191D21),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Timer + Live Equalizer Waveform
          Row(
            children: [
              ScaleTransition(
                scale: _pulseAnimation,
                child: const Icon(Icons.mic_rounded, color: Color(0xFFFF1744), size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _liveAmplitudes.map((amp) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 60),
                        curve: Curves.easeOutCubic,
                        width: 3.2,
                        height: (28 * amp).clamp(4.0, 28.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2E74),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bottom Row: Trash | Pausar pill | Send button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Trash Button
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4081), size: 26),
                onPressed: _handleTrash,
              ),

              // Center Pause Pill
              GestureDetector(
                onTap: _handlePause,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282E33),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Pausar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              // Send Button
              GestureDetector(
                onTap: _handleSend,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF2E74),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- STATE 3: PAUSED RECORDING PREVIEW ---
  Widget _buildPausedPreviewView() {
    final totalMs = _previewTotalDuration.inMilliseconds > 0
        ? _previewTotalDuration.inMilliseconds
        : (_duration > 0 ? _duration * 1000 : 1000);
    final currentMs = _previewPosition.inMilliseconds;
    final progress = (currentMs / totalMs).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF191D21),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Play/Pause + Waveform Preview Track + Duration
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPreviewPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _togglePreviewPlay,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final rel = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                        final targetMs = (rel * totalMs).round();
                        _voiceService.previewPlayer.seek(Duration(milliseconds: targetMs));
                      },
                      child: SizedBox(
                        height: 24,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(_previewWaveformSamples.length, (i) {
                                final barHeight = (5.0 + _previewWaveformSamples[i] * 19.0).clamp(4.0, 24.0);
                                final isPassed = (i / _previewWaveformSamples.length) <= progress;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 50),
                                  width: 3,
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: isPassed ? const Color(0xFFFF2E74) : Colors.white24,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDuration(_isPreviewPlaying ? _previewPosition.inSeconds : _duration),
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bottom Row: Trash | Continuar pill | Send button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Trash
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4081), size: 26),
                onPressed: _handleTrash,
              ),

              // Continuar Button
              GestureDetector(
                onTap: _handleResume,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A1B3B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Continuar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              // Send Button
              GestureDetector(
                onTap: _handleSend,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF2E74),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
