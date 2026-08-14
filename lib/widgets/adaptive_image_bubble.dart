import 'dart:io';
import 'package:flutter/material.dart';

class AdaptiveImageBubble extends StatefulWidget {
  final String mediaUrl;
  final VoidCallback onTap;

  const AdaptiveImageBubble({
    super.key,
    required this.mediaUrl,
    required this.onTap,
  });

  @override
  State<AdaptiveImageBubble> createState() => _AdaptiveImageBubbleState();
}

class _AdaptiveImageBubbleState extends State<AdaptiveImageBubble> {
  double _aspectRatio = 4 / 3; // Default horizontal 4:3
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveDimensions();
  }

  @override
  void didUpdateWidget(covariant AdaptiveImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _resolveDimensions();
    }
  }

  void _resolveDimensions() {
    ImageProvider provider;
    if (widget.mediaUrl.startsWith('http')) {
      provider = NetworkImage(widget.mediaUrl);
    } else {
      provider = FileImage(File(widget.mediaUrl));
    }

    provider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!mounted) return;
          final width = info.image.width.toDouble();
          final height = info.image.height.toDouble();
          if (width > 0 && height > 0) {
            setState(() {
              // 4:3 if horizontal/landscape (w >= h), 3:4 if vertical/portrait (h > w)
              _aspectRatio = width >= height ? (4.0 / 3.0) : (3.0 / 4.0);
              _resolved = true;
            });
          }
        },
        onError: (_, __) {
          if (mounted) {
            setState(() => _resolved = true);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNetwork = widget.mediaUrl.startsWith('http');

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 240,
            maxHeight: 320,
          ),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: isNetwork
                ? Image.network(
                    widget.mediaUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
                    ),
                  )
                : Image.file(
                    File(widget.mediaUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
