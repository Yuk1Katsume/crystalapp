import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/status_service.dart';
import '../services/voice_note_service.dart';

class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final StatusService _statusService = StatusService();
  final ImagePicker _picker = ImagePicker();
  final VoiceNoteService _voiceService = VoiceNoteService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isUploading = false;

  // Selected media for preview/confirmation
  File? _selectedMediaFile;
  String _selectedMediaType = 'image'; // 'image' or 'video'
  final TextEditingController _captionController = TextEditingController();

  // For text status mode
  bool _isTextStatusMode = false;
  final TextEditingController _textStatusController = TextEditingController();
  int _selectedColorIndex = 0;
  final List<Color> _bgColors = [
    const Color(0xFFFF1744), // Neon Pink
    const Color(0xFF7C4DFF), // Purple
    const Color(0xFF00A884), // Emerald
    const Color(0xFFE91E63), // Pink
    const Color(0xFF29B6F6), // Blue
    const Color(0xFFFF6D00), // Orange
    const Color(0xFF1E1E1E), // Dark
  ];

  // Voice recording state
  bool _isRecordingVoice = false;
  int _voiceRecordingDuration = 0;
  StreamSubscription? _voiceDurationSub;
  String? _recordedAudioPath;
  bool _isPlayingAudioPreview = false;

  @override
  void dispose() {
    _captionController.dispose();
    _textStatusController.dispose();
    _voiceDurationSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _selectedMediaFile = File(picked.path);
          _selectedMediaType = 'image';
          _isTextStatusMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e'), backgroundColor: const Color(0xFF1E1E1E)),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked != null) {
        setState(() {
          _selectedMediaFile = File(picked.path);
          _selectedMediaType = 'video';
          _isTextStatusMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar video: $e'), backgroundColor: const Color(0xFF1E1E1E)),
        );
      }
    }
  }

  Future<void> _publishMediaStatus() async {
    if (_selectedMediaFile == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await _selectedMediaFile!.readAsBytes();
      final base64Content = base64Encode(bytes);
      final caption = _captionController.text.trim();

      await _statusService.publishStatus(
        type: _selectedMediaType,
        content: base64Content,
        caption: caption.isNotEmpty ? caption : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Estado multimedia publicado con cifrado E2EE! 🌸'),
            backgroundColor: Color(0xFF1E1E1E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al publicar estado: $e'), backgroundColor: const Color(0xFF1E1E1E)),
        );
      }
    }
  }

  Future<void> _publishTextStatus() async {
    final text = _textStatusController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isUploading = true);
    try {
      final hexColor = '#${_bgColors[_selectedColorIndex].value.toRadixString(16).substring(2).toUpperCase()}';

      await _statusService.publishStatus(
        type: 'text',
        content: text,
        backgroundColor: hexColor,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Estado de texto publicado! 🌸'),
            backgroundColor: Color(0xFF1E1E1E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al publicar estado: $e'), backgroundColor: const Color(0xFF1E1E1E)),
        );
      }
    }
  }

  Future<void> _publishAudioStatus(String audioPath) async {
    setState(() => _isUploading = true);
    try {
      final file = File(audioPath);
      final bytes = await file.readAsBytes();
      final base64Content = base64Encode(bytes);

      await _statusService.publishStatus(
        type: 'audio',
        content: base64Content,
        backgroundColor: '#1E1E1E',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Nota de voz publicada en tu estado con cifrado E2EE! 🎙️🌸'),
            backgroundColor: Color(0xFF1E1E1E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al publicar nota de voz: $e'), backgroundColor: const Color(0xFF1E1E1E)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMediaFile != null) {
      return _buildMediaPreviewScreen();
    }

    if (_isTextStatusMode) {
      return _buildTextStatusComposer();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Añade un estado',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Mode Selector Action Buttons (Texto, Música, Diseño, Audio)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildModeButton(
                    icon: Icons.edit_rounded,
                    label: 'Texto',
                    onTap: () {
                      setState(() {
                        _isTextStatusMode = true;
                      });
                    },
                  ),
                  _buildModeButton(
                    icon: Icons.video_collection_rounded,
                    label: 'Video',
                    onTap: _pickVideo,
                  ),
                  _buildModeButton(
                    icon: Icons.mic_rounded,
                    label: 'Audio',
                    onTap: _showAudioStatusModal,
                  ),
                  _buildModeButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Galería',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // "Acceso Rápido Multimedia ▾" Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: const [
                  Text(
                    'Recientes de la Galería',
                    style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Quick Gallery / Camera / Video Grid
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  // Camera Card
                  GestureDetector(
                    onTap: () => _pickImage(ImageSource.camera),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.camera_alt_outlined, color: Color(0xFF00A884), size: 36),
                          SizedBox(height: 8),
                          Text(
                            'Cámara',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Gallery Photo Card
                  GestureDetector(
                    onTap: () => _pickImage(ImageSource.gallery),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.photo_library_outlined, color: Color(0xFFFF1744), size: 36),
                          SizedBox(height: 8),
                          Text(
                            'Fotos',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Video Picker Card
                  GestureDetector(
                    onTap: _pickVideo,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.videocam_outlined, color: Color(0xFF29B6F6), size: 36),
                          SizedBox(height: 8),
                          Text(
                            'Videos',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Audio Note Status Card
                  GestureDetector(
                    onTap: _showAudioStatusModal,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic_none_rounded, color: Color(0xFFFF6D00), size: 36),
                          SizedBox(height: 8),
                          Text(
                            'Nota de voz',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF262626)),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // Preview screen when an image or video has been captured/selected
  Widget _buildMediaPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _selectedMediaType == 'image'
                  ? Image.file(
                      _selectedMediaFile!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_file_rounded, color: Color(0xFFFF1744), size: 80),
                        const SizedBox(height: 16),
                        Text(
                          _selectedMediaFile!.path.split(Platform.pathSeparator).last,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Video listo para cifrar E2EE y publicar (24h)',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
            ),

            // Top Actions
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () {
                  setState(() {
                    _selectedMediaFile = null;
                  });
                },
              ),
            ),

            // Bottom Caption & Send Bar
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Añade un comentario...',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    backgroundColor: const Color(0xFFFF1744),
                    elevation: 4,
                    shape: const CircleBorder(),
                    onPressed: _isUploading ? null : _publishMediaStatus,
                    child: _isUploading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Text Status Composer (WhatsApp style with color picker)
  Widget _buildTextStatusComposer() {
    final currentColor = _bgColors[_selectedColorIndex];

    return Scaffold(
      backgroundColor: currentColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () {
                      setState(() {
                        _isTextStatusMode = false;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.palette_rounded, color: Colors.white, size: 26),
                    tooltip: 'Cambiar color',
                    onPressed: () {
                      setState(() {
                        _selectedColorIndex = (_selectedColorIndex + 1) % _bgColors.length;
                      });
                    },
                  ),
                ],
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: TextField(
                  controller: _textStatusController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  maxLines: null,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Escribe un estado...',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 26),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: Colors.white,
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: _isUploading ? null : _publishTextStatus,
                child: _isUploading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFFFF1744), strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Color(0xFFFF1744)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioStatusModal() {
    _recordedAudioPath = null;
    _isRecordingVoice = false;
    _voiceRecordingDuration = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 18),
                    const Text('Estado de Nota de Voz (E2EE)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Graba un audio para compartirlo durante 24h', style: TextStyle(color: Colors.white60, fontSize: 13)),
                    const SizedBox(height: 24),

                    // Timer Display
                    Text(
                      '${(_voiceRecordingDuration ~/ 60)}:${(_voiceRecordingDuration % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Color(0xFFFF1744), fontSize: 32, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 24),

                    if (_recordedAudioPath == null) ...[
                      // Recording Button
                      GestureDetector(
                        onTap: () async {
                          if (!_isRecordingVoice) {
                            final ok = await _voiceService.startRecording();
                            if (ok) {
                              setSheetState(() {
                                _isRecordingVoice = true;
                                _voiceRecordingDuration = 0;
                              });
                              _voiceDurationSub?.cancel();
                              _voiceDurationSub = _voiceService.durationStream.listen((d) {
                                if (mounted) {
                                  setSheetState(() => _voiceRecordingDuration = d);
                                }
                              });
                            }
                          } else {
                            final res = await _voiceService.stopRecording();
                            _voiceDurationSub?.cancel();
                            setSheetState(() {
                              _isRecordingVoice = false;
                              _recordedAudioPath = res?['path'] as String?;
                            });
                          }
                        },
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecordingVoice ? const Color(0xFFE53935) : const Color(0xFFFF1744),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFFF1744).withOpacity(0.4), blurRadius: 18, spreadRadius: 2),
                            ],
                          ),
                          child: Icon(
                            _isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isRecordingVoice ? 'Toca para parar la grabación' : 'Toca para empezar a grabar',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ] else ...[
                      // Audio recorded preview controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(_isPlayingAudioPreview ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                            iconSize: 48,
                            color: const Color(0xFFFF1744),
                            onPressed: () async {
                              if (_isPlayingAudioPreview) {
                                await _audioPlayer.pause();
                                setSheetState(() => _isPlayingAudioPreview = false);
                              } else {
                                await _audioPlayer.play(DeviceFileSource(_recordedAudioPath!));
                                setSheetState(() => _isPlayingAudioPreview = true);
                                _audioPlayer.onPlayerComplete.listen((_) {
                                  if (mounted) {
                                    setSheetState(() => _isPlayingAudioPreview = false);
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 28),
                            onPressed: () {
                              setSheetState(() {
                                _recordedAudioPath = null;
                                _voiceRecordingDuration = 0;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF1744),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Publicar estado de voz 🌸', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _publishAudioStatus(_recordedAudioPath!);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
