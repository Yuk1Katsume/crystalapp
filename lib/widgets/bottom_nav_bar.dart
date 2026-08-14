import 'package:flutter/material.dart';
import '../theme/crystal_theme.dart';

class CrimsonBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const CrimsonBottomNavBar({
    super.key,
    this.currentIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: GlassPanel(
        borderRadius: 28.0, // Floating, highly rounded nav bar
        opacity: 0.08,      // 8% white background opacity
        blur: 40.0,         // 40px blur level for extra opacity
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context,
              index: 0,
              icon: Icons.chat_bubble_outline,
              activeIcon: Icons.chat_bubble,
              label: 'Chat',
            ),
            _buildNavItem(
              context,
              index: 1,
              icon: Icons.layers_outlined,
              activeIcon: Icons.layers,
              label: 'Historias',
            ),
            _buildNavItem(
              context,
              index: 2,
              icon: Icons.phone_outlined,
              activeIcon: Icons.phone,
              label: 'Llamadas',
            ),
            _buildNavItem(
              context,
              index: 3,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final bool isActive = index == currentIndex;
    final Color itemColor = isActive
        ? CrimsonPrismTheme.neonRedAccent
        : CrimsonPrismTheme.textSecondary;

    return GestureDetector(
      onTap: () => onTap?.call(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: itemColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter', // Inter for body/navigation labels
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: itemColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
