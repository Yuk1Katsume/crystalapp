class CountryPhoneHelper {
  /// Auto-formats local phone numbers by adding international country code based on length & prefix
  static String formatPhoneNumber(String input) {
    final clean = input.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (clean.isEmpty) return clean;

    // If already has '+' country code, return as is
    if (clean.startsWith('+')) return clean;

    // Spain (+34): 9 digits starting with 6, 7 (mobile) or 8, 9 (landline)
    if (clean.length == 9 && (clean.startsWith('6') || clean.startsWith('7') || clean.startsWith('8') || clean.startsWith('9'))) {
      return '+34$clean';
    }

    // Mexico (+52): 10 digits
    if (clean.length == 10 && (clean.startsWith('55') || clean.startsWith('81') || clean.startsWith('33') || clean.startsWith('56') || clean.startsWith('1'))) {
      return '+52$clean';
    }

    // USA / Canada (+1): 10 digits
    if (clean.length == 10) {
      return '+1$clean';
    }

    // Argentina (+54): 10-11 digits
    if (clean.length == 10 && clean.startsWith('9')) {
      return '+54$clean';
    }

    // Colombia (+57): 10 digits starting with 3
    if (clean.length == 10 && clean.startsWith('3')) {
      return '+57$clean';
    }

    // Default fallback to Spain (+34) if 9 digits
    if (clean.length == 9) {
      return '+34$clean';
    }

    return '+$clean';
  }
}
