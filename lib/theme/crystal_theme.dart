import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CrystalTheme {
  static ThemeData get darkTheme => CrimsonPrismTheme.darkTheme;
}

/// Visual identity definitions for 'Crimson Prism'.
class CrimsonPrismTheme {
  // Hex Colors
  static const Color obsidianBackground = Color(0xFF0A0A0A);
  static const Color neonRedAccent = Color(0xFFFF1744);
  
  // Dark grey surface variants
  static const Color surfacePrimary = Color(0xFF121212);
  static const Color surfaceSecondary = Color(0xFF1E1E1E);
  static const Color surfaceTertiary = Color(0xFF262626);
  
  // Text colors
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);

  /// Generates the Dark ThemeData matching the Crimson Prism identity.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: obsidianBackground,
      colorScheme: const ColorScheme.dark(
        surface: surfacePrimary,
        onSurface: textPrimary,
        primary: neonRedAccent,
        onPrimary: Colors.white,
        secondary: neonRedAccent,
        onSecondary: Colors.white,
        outline: surfaceTertiary,
      ),
      textTheme: TextTheme(
        // 'Geist' for headers / titles
        displayLarge: GoogleFonts.getFont(
          'Geist',
          fontSize: 57,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displayMedium: GoogleFonts.getFont(
          'Geist',
          fontSize: 45,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displaySmall: GoogleFonts.getFont(
          'Geist',
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineLarge: GoogleFonts.getFont(
          'Geist',
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.getFont(
          'Geist',
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: GoogleFonts.getFont(
          'Geist',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.getFont(
          'Geist',
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.getFont(
          'Geist',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: GoogleFonts.getFont(
          'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        
        // 'Inter' for body text
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: textMuted,
        ),

        // 'JetBrains Mono' for metadata/labels/tags
        labelLarge: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: neonRedAccent,
        ),
        labelMedium: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.normal,
          color: textMuted,
        ),
      ),
    );
  }
}

/// A reusable widget that implements a glass panel effect.
/// It uses BackdropFilter to blur the content underneath and overlays
/// a transparent white surface with a subtle border.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 8.0,
    this.blur = 20.0,
    this.opacity = 0.04,
    this.padding,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity), // Fondo blanco con opacidad configurada
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10), // Borde sutil al 10% de opacidad
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
