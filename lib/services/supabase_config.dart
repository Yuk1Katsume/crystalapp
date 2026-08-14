import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://qxnsdjykzkkikilxaqnv.supabase.co';
  static const String anonKey = 'sb_publishable_mUZuacNconoEDYTYg6DEDA_dkL_ZknI';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
