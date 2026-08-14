import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

class RoleService {
  static const String superAdminUsername = 'yuk1katsume';
  static bool? _cachedIsSuperAdmin;

  /// Returns true if the currently logged in user is @Yuk1Katsume
  /// Note: Completely stealth, does not display any visible role badges to other users.
  static Future<bool> isSuperAdmin() async {
    if (_cachedIsSuperAdmin != null) return _cachedIsSuperAdmin!;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Check SharedPreferences username cache
      final prefs = await SharedPreferences.getInstance();
      final localUsername = prefs.getString('current_username')?.trim().toLowerCase();
      if (localUsername == superAdminUsername) {
        _cachedIsSuperAdmin = true;
        return true;
      }

      // Check Supabase users table
      final res = await SupabaseConfig.client
          .from('users')
          .select('username')
          .eq('id', user.uid)
          .maybeSingle();

      if (res != null) {
        final dbUsername = res['username']?.toString().trim().toLowerCase();
        if (dbUsername == superAdminUsername) {
          _cachedIsSuperAdmin = true;
          return true;
        }
      }

      // Also check if display name matches
      final displayName = user.displayName?.trim().toLowerCase();
      if (displayName == superAdminUsername) {
        _cachedIsSuperAdmin = true;
        return true;
      }
    } catch (_) {}

    _cachedIsSuperAdmin = false;
    return false;
  }

  /// Synchronous quick check (defaults to true if cached, or falls back to async)
  static bool get isCurrentSuperAdmin => _cachedIsSuperAdmin ?? false;

  /// Clear cached role on logout or profile update
  static void invalidateCache() {
    _cachedIsSuperAdmin = null;
  }
}
