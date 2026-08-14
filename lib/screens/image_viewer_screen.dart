import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message_model.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imagePathOrUrl;
  final Message message;
  final String? senderName;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onStar;

  const ImageViewerScreen({
    super.key,
    required this.imagePathOrUrl,
    required this.message,
    this.senderName,
    this.onReply,
    this.onForward,
    this.onStar,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _isStarred = false;
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final isNetwork = widget.imagePathOrUrl.startsWith('http');
    final formattedTime =
        '${widget.message.timestamp.hour.toString().padLeft(2, '0')}:${widget.message.timestamp.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.senderName ?? 'Foto',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              formattedTime,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isStarred ? Icons.star : Icons.star_border,
              color: _isStarred ? Colors.amber : Colors.white,
            ),
            tooltip: 'Destacar',
            onPressed: () {
              setState(() {
                _isStarred = !_isStarred;
              });
              widget.onStar?.call();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isStarred ? '⭐ Mensaje destacado' : 'Mensaje no destacado'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.reply, color: Colors.white),
            tooltip: 'Responder',
            onPressed: () {
              Navigator.pop(context);
              widget.onReply?.call();
            },
          ),
          IconButton(
            icon: const Icon(Icons.forward, color: Colors.white),
            tooltip: 'Reenviar',
            onPressed: () {
              widget.onForward?.call();
            },
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onDoubleTap: _resetZoom,
          child: InteractiveViewer(
            transformationController: _transformController,
            panEnabled: true,
            minScale: 0.8,
            maxScale: 4.0,
            child: isNetwork
                ? Image.network(
                    widget.imagePathOrUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    ),
                  )
                : Image.file(
                    File(widget.imagePathOrUrl),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
