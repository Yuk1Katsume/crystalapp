import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme/crystal_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'firebase_options.dart';
import 'services/supabase_config.dart';
import 'services/update_service.dart';
import 'services/call_notification_service.dart';
import 'services/message_notification_service.dart';
import 'services/auth_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await SupabaseConfig.initialize();
  await CallNotificationService().initialize();
  await MessageNotificationService().initialize();
  runApp(const CrystalApp());
}

class CrystalApp extends StatefulWidget {
  const CrystalApp({super.key});

  @override
  State<CrystalApp> createState() => _CrystalAppState();
}

class _CrystalAppState extends State<CrystalApp> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService.setOnlineStatus(true);
    // Periodic heartbeat every 45 seconds to keep last_seen fresh
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _authService.setOnlineStatus(true);
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _authService.setOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _authService.setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _authService.setOnlineStatus(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'CrystalApp 🌸',
      debugShowCheckedModeBanner: false,
      theme: CrystalTheme.darkTheme,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0A0A0A),
              body: Center(child: CircularProgressIndicator(color: Color(0xFFFF1744))),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            _authService.setOnlineStatus(true);
            return const HomeScreen();
          }
          return const AuthScreen();
        },
      ),
      routes: {
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/chat': (context) => const ChatScreen(),
      },
      builder: (context, child) => _UpdateChecker(child: child!),
    );
  }
}

/// Wraps the entire app and checks for updates on startup and every 5 minutes while open
class _UpdateChecker extends StatefulWidget {
  final Widget child;
  const _UpdateChecker({required this.child});

  @override
  State<_UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<_UpdateChecker> {
  Timer? _timer;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    // Check after UI is initialized
    Future.delayed(const Duration(seconds: 1), _checkUpdate);
    // Periodic check every 3 minutes while app is open
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _checkUpdate());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    if (_dialogShowing) return;
    final update = await UpdateService.checkForUpdate();
    if (update != null && !_dialogShowing) {
      final navContext = navigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        _dialogShowing = true;
        await showUpdateDialog(navContext, update);
        _dialogShowing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

