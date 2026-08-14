import 'package:crypto/crypto.dart';

class CryptoService {
  static String hashString(String input) {
    return sha256.convert(input.codeUnits).toString();
  }
}
