import 'package:flutter/material.dart';
import '../theme/crystal_theme.dart';
import '../widgets/top_app_bar.dart';
import '../widgets/bottom_nav_bar.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background decorative glowing elements (deep blurred ambient lights)
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CrimsonPrismTheme.neonRedAccent.withValues(alpha: 0.15),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CrimsonPrismTheme.neonRedAccent.withValues(alpha: 0.10),
                    blurRadius: 150,
                    spreadRadius: 80,
                  ),
                ],
              ),
            ),
          ),
          
          // Main Scrollable Content with Silver Header
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Translucent Silver Top App Bar
              const CrimsonTopAppBar(),
              
              // Content Body
              SliverPadding(
                padding: const EdgeInsets.only(
                  left: 24.0,
                  right: 24.0,
                  top: 24.0,
                  bottom: 140.0, // Extra padding at bottom to avoid overlap with bottom nav bar
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Title section
                    Text(
                      'Crimson Prism',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Tag/Metadata row using JetBrains Mono
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: CrimsonPrismTheme.neonRedAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: CrimsonPrismTheme.neonRedAccent.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'SYSTEM: ACTIVE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: CrimsonPrismTheme.neonRedAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'v0.1.0-alpha',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Main GlassPanel Card
                    GlassPanel(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clean Architecture',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'El proyecto ha sido inicializado con una estructura modular y limpia. '
                            'Los estilos visuales están centralizados en un tema personalizado.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Icon(
                                Icons.folder_open_outlined,
                                size: 16,
                                color: CrimsonPrismTheme.neonRedAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'lib/theme/crystal_theme.dart',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: CrimsonPrismTheme.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Additional info in secondary GlassPanel
                    GlassPanel(
                      borderRadius: 16.0,
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: CrimsonPrismTheme.neonRedAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Glassmorphism',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Fondo blanco al 4% de opacidad y desenfoque de 20px.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // A widget showing font definitions
                    GlassPanel(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TIPOGRAFÍA',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: CrimsonPrismTheme.neonRedAccent,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Titulares: Geist Font',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cuerpo de texto: Inter Font',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Metadatos: JetBrains Mono',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          
          // Floating Bottom Navigation Bar positioned over the background
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CrimsonBottomNavBar(
              onTap: (index) {
                Navigator.pushNamed(context, '/auth');
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF1744),
        icon: const Icon(Icons.arrow_forward, color: Colors.white),
        label: const Text('EMPEZAR (LOGIN/SMS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.pushNamed(context, '/auth');
        },
      ),
    );
  }
}
