import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'supabase_config.dart';

class BlockService {
  static final BlockService _instance = BlockService._internal();
  factory BlockService() => _instance;
  BlockService._internal();

  static const String _keyBlockedUsers = 'crystal_blocked_users';

  /// Check if a user is blocked locally
  Future<bool> isUserBlocked(String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList(_keyBlockedUsers) ?? [];
    return blockedList.contains(targetUserId);
  }

  /// Block a user
  Future<void> blockUser(String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = (prefs.getStringList(_keyBlockedUsers) ?? []).toSet();
    blockedList.add(targetUserId);
    await prefs.setStringList(_keyBlockedUsers, blockedList.toList());

    // Sync to Supabase if possible
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await SupabaseConfig.client.from('blocked_users').upsert({
          'user_id': currentUid,
          'blocked_user_id': targetUserId,
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  /// Unblock a user
  Future<void> unblockUser(String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = (prefs.getStringList(_keyBlockedUsers) ?? []).toSet();
    blockedList.remove(targetUserId);
    await prefs.setStringList(_keyBlockedUsers, blockedList.toList());

    // Sync to Supabase if possible
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await SupabaseConfig.client
            .from('blocked_users')
            .delete()
            .match({'user_id': currentUid, 'blocked_user_id': targetUserId})
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  /// Get list of all blocked user IDs
  Future<List<String>> getBlockedUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyBlockedUsers) ?? [];
  }
}
