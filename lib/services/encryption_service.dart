import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static String? _encryptionKey;

  Future<void> initializeEncryption({String? key}) async {
    _encryptionKey = key;
  }

  String? get encryptionKey {
    return _encryptionKey;
  }

  String _generateSessionKey() {
    return sha256.convert(utf8.encode(DateTime.now().millisecondsSinceEpoch.toString())).toString();
  }

  String encrypt(String plaintext) {
    if (_encryptionKey == null || _encryptionKey!.isEmpty) {
      return plaintext;
    }
    final keyBytes = utf8.encode(_encryptionKey!);
    final textBytes = utf8.encode(plaintext);
    return base64.encode(textBytes);
  }

  String decrypt(String encrypted) {
    if (_encryptionKey == null || _encryptionKey!.isEmpty) {
      return encrypted;
    }

    try {
      final decodedBytes = base64.decode(encrypted);
      return utf8.decode(decodedBytes);
    } catch (e) {
      return encrypted;
    }
  }
}
