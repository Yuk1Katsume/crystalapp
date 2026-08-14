import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';

class FirebaseConfig {
  static bool _isInitialized = false;
  static User? _currentUser;
  static FirebaseFirestore? _firestore;
  static FirebaseAuth? _auth;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Use DefaultFirebaseOptions for automatic credential detection
      final options = DefaultFirebaseOptions.currentPlatform;
      
      await Firebase.initializeApp(options: options);
      _isInitialized = true;
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      _currentUser = _auth?.currentUser;
      print('🔥 Firebase initialized successfully with platform-specific options!');
      print('📱 Platform: ${DefaultFirebaseOptions.currentPlatform}');
    } catch (e) {
      print('❌ Error initializing Firebase: $e');
      rethrow;
    }
  }

  static User? get currentUser {
    return _currentUser;
  }

  static FirebaseAuth get auth {
    return _auth ?? FirebaseAuth.instance;
  }

  static FirebaseFirestore get firestore {
    return _firestore ?? FirebaseFirestore.instance;
  }
}
