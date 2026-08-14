import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/crystal_theme.dart';

class CrimsonTopAppBar extends StatelessWidget {
  const CrimsonTopAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    
    return SliverPersistentHeader(
      pinned: true,
      delegate: _GlassTopAppBarDelegate(statusBarHeight: statusBarHeight),
    );
  }
}

class _GlassTopAppBarDelegate extends SliverPersistentHeaderDelegate {
  final double statusBarHeight;

  _GlassTopAppBarDelegate({required this.statusBarHeight});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double totalHeight = 56.0 + statusBarHeight;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          height: totalHeight,
          padding: EdgeInsets.only(top: statusBarHeight),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04), // Fondo blanco al 4% de opacidad
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.10), // Borde sutil al 10% de opacidad
                width: 1.0,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Lock icon on the left
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: Icon(
                    Icons.lock_outline,
                    color: CrimsonPrismTheme.neonRedAccent,
                    size: 20,
                  ),
                ),
              ),
              // Centered Title
              Align(
                alignment: Alignment.center,
                child: Text(
                  'CRIMSON PRISM',
                  style: GoogleFonts.getFont(
                    'Geist',
                    color: CrimsonPrismTheme.neonRedAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 56.0 + statusBarHeight;

  @override
  double get minExtent => 56.0 + statusBarHeight;

  @override
  bool shouldRebuild(covariant _GlassTopAppBarDelegate oldDelegate) {
    return statusBarHeight != oldDelegate.statusBarHeight;
  }
}
