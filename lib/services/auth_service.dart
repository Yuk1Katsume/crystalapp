import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'e2ee_service.dart';
import 'supabase_config.dart';

class AuthService {
  final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance;
  SupabaseClient get _supabase => SupabaseConfig.client;

  fb_auth.User? get currentUser => _firebaseAuth.currentUser;

  Stream<fb_auth.User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Check if a phone number already has a registered user in Supabase
  Future<Map<String, dynamic>?> getUserByPhone(String phoneNumber) async {
    try {
      final formatted = phoneNumber.trim().replaceAll(' ', '');
      final response = await _supabase
          .from('users')
          .select('id, username, display_name, phone')
          .eq('phone', formatted)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Check if username is already taken in Supabase
  Future<bool> isUsernameAvailable(String username) async {
    final cleanUsername = username.toLowerCase().trim().replaceAll('@', '');
    try {
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('username', cleanUsername)
          .maybeSingle();
      return response == null;
    } catch (e) {
      return true;
    }
  }

  /// Initiates Phone Number Verification with Firebase Auth
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(fb_auth.PhoneAuthCredential) onVerificationCompleted,
    required Function(fb_auth.FirebaseAuthException) onVerificationFailed,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String verificationId) onCodeAutoRetrievalTimeout,
  }) async {
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout,
      timeout: const Duration(seconds: 60),
    );
  }

  /// Signs in with SMS OTP Code
  Future<fb_auth.UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
    required String username,
    required String displayName,
  }) async {
    final credential = fb_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    if (userCredential.user != null) {
      await registerOrUpdateUserInSupabase(
        userCredential.user!,
        username: username,
        displayName: displayName,
      );
    }
    return userCredential;
  }

  /// Registers or updates user profile in Supabase database
  Future<void> registerOrUpdateUserInSupabase(
    fb_auth.User user, {
    required String username,
    required String displayName,
  }) async {
    final e2ee = E2EEService();
    final keyPair = await e2ee.getOrCreateKeyPair();

    final cleanUsername = username.isEmpty ? 'user_${user.uid.substring(0, 5)}' : username.toLowerCase().trim().replaceAll('@', '');
    final cleanDisplayName = displayName.isEmpty ? cleanUsername : displayName;

    final data = {
      'id': user.uid,
      'phone': user.phoneNumber ?? '',
      'username': cleanUsername,
      'display_name': cleanDisplayName,
      'public_key': keyPair['publicKey'],
      'is_online': true,
      'last_seen': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase.from('users').upsert(data);
    } catch (e) {
      // Ignore if table temporarily missing
    }
  }

  /// Search users matching query in Supabase
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final cleanQuery = query.toLowerCase().trim().replaceAll('@', '');

    try {
      final currentUid = currentUser?.uid;
      final List<dynamic> response = await _supabase
          .from('users')
          .select()
          .neq('id', currentUid ?? '');

      List<Map<String, dynamic>> results = [];

      for (var row in response) {
        final item = Map<String, dynamic>.from(row);
        final username = (item['username'] ?? '').toString().toLowerCase();
        final displayName = (item['display_name'] ?? item['name'] ?? '').toString().toLowerCase();
        final phone = (item['phone'] ?? '').toString();

        if (cleanQuery.isEmpty ||
            username.contains(cleanQuery) ||
            displayName.contains(cleanQuery) ||
            phone.contains(cleanQuery)) {
          results.add({
            'uid': item['id'],
            'username': item['username'],
            'displayName': item['display_name'],
            'phone': item['phone'],
            'publicKey': item['public_key'],
            'isOnline': item['is_online'] ?? false,
          });
        }
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Update online status in Supabase
  Future<void> setOnlineStatus(bool isOnline) async {
    if (currentUser == null) return;
    try {
      await _supabase.from('users').update({
        'is_online': isOnline,
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', currentUser!.uid);
    } catch (e) {
      // Ignore
    }
  }

  /// Sign Out
  Future<void> signOut() async {
    if (currentUser != null) {
      await setOnlineStatus(false);
    }
    await _firebaseAuth.signOut();
  }
}
