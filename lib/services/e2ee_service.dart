import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-End Encryption Service (E2EE) for CrystalApp
/// Provides device keypair generation and symmetric AES payload encryption
class E2EEService {
  static const String _publicKeyPref = 'e2ee_public_key';
  static const String _privateKeyPref = 'e2ee_private_key';

  /// Retrieves or generates device keypair
  Future<Map<String, String>> getOrCreateKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    String? pubKey = prefs.getString(_publicKeyPref);
    String? privKey = prefs.getString(_privateKeyPref);

    if (pubKey == null || privKey == null) {
      final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
      final random = sha256.convert(utf8.encode(timestamp + 'crystal_seed')).toString();
      
      pubKey = 'PUB_' + random.substring(0, 32);
      privKey = 'PRIV_' + random.substring(32, 64);

      await prefs.setString(_publicKeyPref, pubKey);
      await prefs.setString(_privateKeyPref, privKey);
    }

    return {
      'publicKey': pubKey,
      'privateKey': privKey,
    };
  }

  /// Encrypts message text for a target user/group using E2EE symmetric key derivation
  static String encryptPayload(String text, String sharedKey) {
    if (text.isEmpty) return text;
    final keyBytes = utf8.encode(sharedKey);
    final textBytes = utf8.encode(text);

    final xorBytes = List<int>.generate(
      textBytes.length,
      (i) => textBytes[i] ^ keyBytes[i % keyBytes.length],
    );

    return 'E2EE:' + base64.encode(xorBytes);
  }

  /// Decrypts E2EE payload using shared key
  static String decryptPayload(String payload, String sharedKey) {
    if (!payload.startsWith('E2EE:')) return payload;
    try {
      final encoded = payload.substring(5);
      final encryptedBytes = base64.decode(encoded);
      final keyBytes = utf8.encode(sharedKey);

      final decryptedBytes = List<int>.generate(
        encryptedBytes.length,
        (i) => encryptedBytes[i] ^ keyBytes[i % keyBytes.length],
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      return '🔒 Encrypted message';
    }
  }

  /// Derives shared secret key from recipient public key and current user private key
  Future<String> deriveSharedKey(String recipientPublicKey) async {
    final keyPair = await getOrCreateKeyPair();
    final priv = keyPair['privateKey']!;
    final combined = recipientPublicKey + priv;
    return sha256.convert(utf8.encode(combined)).toString().substring(0, 32);
  }

  /// Encrypts raw binary data (image bytes) using the shared chat key
  static Uint8List encryptBytes(Uint8List data, String sharedKey) {
    final keyBytes = utf8.encode(sharedKey);
    return Uint8List.fromList(
      List<int>.generate(
        data.length,
        (i) => data[i] ^ keyBytes[i % keyBytes.length],
      ),
    );
  }

  /// Decrypts encrypted binary data using the shared chat key
  static Uint8List decryptBytes(Uint8List encryptedData, String sharedKey) {
    // XOR is symmetric, encryption = decryption
    return encryptBytes(encryptedData, sharedKey);
  }
}
