import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/status_service.dart';

class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final StatusService _statusService = StatusService();
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  // Selected media for preview/confirmation
  File? _selectedImageFile;
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

  @override
  void dispose() {
    _captionController.dispose();
    _textStatusController.dispose();
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
          _selectedImageFile = File(picked.path);
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

  Future<void> _publishMediaStatus() async {
    if (_selectedImageFile == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await _selectedImageFile!.readAsBytes();
      final base64Content = base64Encode(bytes);
      final caption = _captionController.text.trim();

      await _statusService.publishStatus(
        type: 'image',
        content: base64Content,
        caption: caption.isNotEmpty ? caption : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Estado publicado con cifrado E2EE! 🌸'),
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

  @override
  Widget build(BuildContext context) {
    if (_selectedImageFile != null) {
      return _buildImagePreviewScreen();
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
                    icon: Icons.music_note_rounded,
                    label: 'Música',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selector de música en desarrollo 🎵'), backgroundColor: Color(0xFF1E1E1E)),
                      );
                    },
                  ),
                  _buildModeButton(
                    icon: Icons.grid_view_rounded,
                    label: 'Diseño',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Plantillas de diseño en desarrollo 🪟'), backgroundColor: Color(0xFF1E1E1E)),
                      );
                    },
                  ),
                  _buildModeButton(
                    icon: Icons.mic_rounded,
                    label: 'Audio',
                    onTap: () {
                      _showAudioStatusDialog();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // "Recientes ▾" Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: const [
                  Text(
                    'Recientes',
                    style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Gallery / Camera Grid
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
                  // Gallery Card
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
                            'Galería',
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

  // Preview screen when an image has been captured/selected
  Widget _buildImagePreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Image
            Center(
              child: Image.file(
                _selectedImageFile!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
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
                    _selectedImageFile = null;
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
            // Top Controls
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

            // Center Big Text Input
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

            // Bottom Send FAB
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

  void _showAudioStatusDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Graba un mensaje de voz en un chat o cárgalo como estado 🎤'),
        backgroundColor: Color(0xFF1E1E1E),
      ),
    );
  }
}
