import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'supabase_config.dart';

class MatchedContact {
  final String contactName;
  final String rawPhoneNumber;
  final String? appUserId;
  final String? appUsername;
  final String? appDisplayName;
  final String? avatarUrl;
  final String? publicKey;
  final bool isOnline;
  final bool isRegistered;

  MatchedContact({
    required this.contactName,
    required this.rawPhoneNumber,
    this.appUserId,
    this.appUsername,
    this.appDisplayName,
    this.avatarUrl,
    this.publicKey,
    this.isOnline = false,
    required this.isRegistered,
  });

  Map<String, dynamic> toUserMap() {
    return {
      'id': appUserId,
      'username': appUsername ?? '',
      'display_name': contactName.isNotEmpty ? contactName : (appDisplayName ?? appUsername ?? ''),
      'phone': rawPhoneNumber,
      'avatar_url': avatarUrl,
      'public_key': publicKey,
      'is_online': isOnline,
    };
  }
}

class ContactsServiceManager {
  static final ContactsServiceManager _instance = ContactsServiceManager._internal();
  factory ContactsServiceManager() => _instance;
  ContactsServiceManager._internal();

  static const MethodChannel _channel = MethodChannel('com.crimsonprism.crystalapp/contacts');

  final AuthService _authService = AuthService();
  SupabaseClient get _supabase => SupabaseConfig.client;

  List<MatchedContact> _cachedRegisteredContacts = [];
  List<MatchedContact> _cachedUnregisteredContacts = [];
  bool _isLoading = false;

  List<MatchedContact> get registeredContacts => _cachedRegisteredContacts;
  List<MatchedContact> get unregisteredContacts => _cachedUnregisteredContacts;
  bool get isLoading => _isLoading;

  /// Request contact reading permissions
  Future<bool> requestPermission() async {
    final status = await Permission.contacts.status;
    if (status.isGranted) return true;
    final result = await Permission.contacts.request();
    return result.isGranted;
  }

  /// Normalizes a phone number into canonical variations (with and without country codes)
  Set<String> getPhoneVariations(String raw) {
    String digitsOnly = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digitsOnly.isEmpty) return {};

    Set<String> variations = {digitsOnly};

    // If starts with +34, extract country-less variation
    if (digitsOnly.startsWith('+34') && digitsOnly.length == 12) {
      variations.add(digitsOnly.substring(3)); // 9 digits
      variations.add('0034${digitsOnly.substring(3)}');
    } else if (digitsOnly.startsWith('0034') && digitsOnly.length == 13) {
      variations.add(digitsOnly.substring(4));
      variations.add('+34${digitsOnly.substring(4)}');
    } else if (digitsOnly.length == 9 && (digitsOnly.startsWith('6') || digitsOnly.startsWith('7') || digitsOnly.startsWith('8') || digitsOnly.startsWith('9'))) {
      variations.add('+34$digitsOnly');
      variations.add('0034$digitsOnly');
    }

    if (digitsOnly.startsWith('+')) {
      variations.add(digitsOnly.substring(1));
    }

    return variations;
  }

  /// Sync device contacts with registered users in Supabase
  Future<Map<String, List<MatchedContact>>> syncContacts() async {
    _isLoading = true;

    final hasPermission = await requestPermission();
    if (!hasPermission) {
      _isLoading = false;
      return {'registered': [], 'unregistered': []};
    }

    try {
      final currentUid = _authService.currentUser?.uid;

      // 1. Read device contacts via native MethodChannel
      final List<dynamic>? rawContacts = await _channel.invokeMethod<List<dynamic>>('getContacts');
      final List<Map<String, String>> deviceContacts = (rawContacts ?? []).map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': (map['name'] ?? '').toString(),
          'phone': (map['phone'] ?? '').toString(),
        };
      }).toList();

      // 2. Fetch registered users from Supabase
      final List<dynamic> allAppUsers = await _supabase
          .from('users')
          .select('id, username, display_name, phone, avatar_url, public_key, is_online, last_seen');

      // Index registered users by phone variations
      final Map<String, Map<String, dynamic>> phoneToUser = {};
      for (final u in allAppUsers) {
        if (u is Map<String, dynamic>) {
          final uPhone = (u['phone'] ?? '').toString();
          if (uPhone.isNotEmpty && u['id'] != currentUid) {
            for (final v in getPhoneVariations(uPhone)) {
              phoneToUser[v] = u;
            }
          }
        }
      }

      final List<MatchedContact> registered = [];
      final List<MatchedContact> unregistered = [];
      final Set<String> seenUserIds = {};
      final Set<String> seenPhones = {};

      for (final contact in deviceContacts) {
        final contactName = contact['name']?.trim() ?? '';
        final rawNumber = contact['phone']?.trim() ?? '';
        if (rawNumber.isEmpty) continue;

        final variations = getPhoneVariations(rawNumber);
        if (variations.isEmpty) continue;

        Map<String, dynamic>? matchedUser;
        for (final v in variations) {
          if (phoneToUser.containsKey(v)) {
            matchedUser = phoneToUser[v];
            break;
          }
        }

        if (matchedUser != null) {
          final uid = matchedUser['id'].toString();
          if (!seenUserIds.contains(uid)) {
            seenUserIds.add(uid);
            registered.add(MatchedContact(
              contactName: contactName.isNotEmpty ? contactName : (matchedUser['display_name'] ?? matchedUser['username'] ?? rawNumber),
              rawPhoneNumber: rawNumber,
              appUserId: uid,
              appUsername: matchedUser['username'] ?? '',
              appDisplayName: matchedUser['display_name'] ?? '',
              avatarUrl: matchedUser['avatar_url'],
              publicKey: matchedUser['public_key'],
              isOnline: matchedUser['is_online'] == true,
              isRegistered: true,
            ));
          }
        } else {
          final primaryVariation = variations.first;
          if (!seenPhones.contains(primaryVariation) && contactName.isNotEmpty) {
            seenPhones.add(primaryVariation);
            unregistered.add(MatchedContact(
              contactName: contactName,
              rawPhoneNumber: rawNumber,
              isRegistered: false,
            ));
          }
        }
      }

      registered.sort((a, b) => a.contactName.toLowerCase().compareTo(b.contactName.toLowerCase()));
      unregistered.sort((a, b) => a.contactName.toLowerCase().compareTo(b.contactName.toLowerCase()));

      _cachedRegisteredContacts = registered;
      _cachedUnregisteredContacts = unregistered;
      _isLoading = false;

      return {
        'registered': registered,
        'unregistered': unregistered,
      };
    } catch (e) {
      _isLoading = false;
      return {
        'registered': _cachedRegisteredContacts,
        'unregistered': _cachedUnregisteredContacts,
      };
    }
  }

  /// Get contact name from agenda for a specific user ID or phone number
  Future<String?> getContactNameForUser(String userId, [String? phone]) async {
    if (_cachedRegisteredContacts.isEmpty) {
      await syncContacts();
    }
    for (final c in _cachedRegisteredContacts) {
      if (c.appUserId == userId) {
        return c.contactName;
      }
    }
    if (phone != null && phone.isNotEmpty) {
      final phoneVars = getPhoneVariations(phone);
      for (final c in _cachedRegisteredContacts) {
        if (phoneVars.any((v) => getPhoneVariations(c.rawPhoneNumber).contains(v))) {
          return c.contactName;
        }
      }
      for (final c in _cachedUnregisteredContacts) {
        if (phoneVars.any((v) => getPhoneVariations(c.rawPhoneNumber).contains(v))) {
          return c.contactName;
        }
      }
    }
    return null;
  }
}
