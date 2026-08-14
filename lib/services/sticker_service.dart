import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

class DynamicSticker {
  final String id;
  final String imageUrl;
  final String? name;
  final DateTime createdAt;

  DynamicSticker({
    required this.id,
    required this.imageUrl,
    this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageUrl': imageUrl,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DynamicSticker.fromJson(Map<String, dynamic> json) => DynamicSticker(
        id: json['id'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        name: json['name'] as String?,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class StickerService {
  static const String _kLocalStickersKey = 'custom_stickers_cache';
  static const String _kFavoriteStickersKey = 'favorite_stickers_cache';

  /// Load custom stickers (from Supabase Storage/table + local cache)
  static Future<List<DynamicSticker>> loadCustomStickers() async {
    final List<DynamicSticker> results = [];

    // 1. Read local cache first for instant UI response
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_kLocalStickersKey);
      if (localJson != null) {
        final List<dynamic> list = jsonDecode(localJson);
        results.addAll(list.map((e) => DynamicSticker.fromJson(e as Map<String, dynamic>)));
      }
    } catch (_) {}

    // 2. Fetch from Supabase stickers table or storage
    try {
      final res = await SupabaseConfig.client
          .from('stickers')
          .select('id, image_url, name, created_at')
          .order('created_at', ascending: false);

      final List<DynamicSticker> remoteStickers = [];
      for (final row in res) {
        remoteStickers.add(DynamicSticker(
          id: row['id']?.toString() ?? '',
          imageUrl: row['image_url']?.toString() ?? '',
          name: row['name']?.toString(),
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }

      if (remoteStickers.isNotEmpty) {
        // Cache remotely fetched stickers
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLocalStickersKey, jsonEncode(remoteStickers.map((s) => s.toJson()).toList()));
        return remoteStickers;
      }
    } catch (_) {}

    return results;
  }

  /// Create and upload a new sticker from image file (Exclusive for Admin @Yuk1Katsume)
  static Future<DynamicSticker?> createSticker({
    required File imageFile,
    String? name,
  }) async {
    try {
      final ext = imageFile.path.split('.').last;
      final stickerId = 'stk_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = '$stickerId.$ext';

      // 1. Upload to Supabase Storage avatars or stickers bucket
      String publicUrl = '';
      try {
        await SupabaseConfig.client.storage.from('stickers').upload(fileName, imageFile);
        publicUrl = SupabaseConfig.client.storage.from('stickers').getPublicUrl(fileName);
      } catch (_) {
        // Fallback to avatars bucket if stickers bucket doesn't exist
        await SupabaseConfig.client.storage.from('avatars').upload(fileName, imageFile);
        publicUrl = SupabaseConfig.client.storage.from('avatars').getPublicUrl(fileName);
      }

      final newSticker = DynamicSticker(
        id: stickerId,
        imageUrl: publicUrl,
        name: name ?? 'Sticker',
        createdAt: DateTime.now(),
      );

      // 2. Persist to Supabase stickers table if exists
      try {
        await SupabaseConfig.client.from('stickers').insert({
          'id': newSticker.id,
          'image_url': newSticker.imageUrl,
          'name': newSticker.name,
          'created_at': newSticker.createdAt.toIso8601String(),
        });
      } catch (_) {}

      // 3. Update local cache
      final currentList = await loadCustomStickers();
      final updatedList = [newSticker, ...currentList.where((s) => s.id != newSticker.id)];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocalStickersKey, jsonEncode(updatedList.map((s) => s.toJson()).toList()));

      return newSticker;
    } catch (e) {
      return null;
    }
  }

  /// Load user's favorite stickers
  static Future<List<DynamicSticker>> getFavoriteStickers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kFavoriteStickersKey);
      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => DynamicSticker.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Check if a sticker URL is in favorites
  static Future<bool> isFavorite(String imageUrl) async {
    final favorites = await getFavoriteStickers();
    return favorites.any((s) => s.imageUrl == imageUrl);
  }

  /// Add a sticker to favorites
  static Future<void> addFavorite(String imageUrl, {String? name, String? id}) async {
    final favorites = await getFavoriteStickers();
    if (favorites.any((s) => s.imageUrl == imageUrl)) return;

    final newFav = DynamicSticker(
      id: id ?? 'fav_${DateTime.now().millisecondsSinceEpoch}',
      imageUrl: imageUrl,
      name: name,
      createdAt: DateTime.now(),
    );

    favorites.insert(0, newFav);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavoriteStickersKey, jsonEncode(favorites.map((s) => s.toJson()).toList()));
  }

  /// Remove a sticker from favorites
  static Future<void> removeFavorite(String imageUrl) async {
    final favorites = await getFavoriteStickers();
    favorites.removeWhere((s) => s.imageUrl == imageUrl);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavoriteStickersKey, jsonEncode(favorites.map((s) => s.toJson()).toList()));
  }

  /// Toggle sticker favorite status
  static Future<bool> toggleFavorite(String imageUrl, {String? name, String? id}) async {
    final isFav = await isFavorite(imageUrl);
    if (isFav) {
      await removeFavorite(imageUrl);
      return false;
    } else {
      await addFavorite(imageUrl, name: name, id: id);
      return true;
    }
  }
}
