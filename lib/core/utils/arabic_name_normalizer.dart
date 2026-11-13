/// Arabic & mixed-script name normalization utilities for smart search and
/// duplicate-entry warnings on customers and suppliers.
///
/// Handles:
/// - Unifying Alef variants (`أ`, `إ`, `آ`, `ٱ` -> `ا`)
/// - Unifying Alef Maksura / Ya (`ى` -> `ي`)
/// - Unifying Ta Marbuta / Ha (`ة` -> `ه`)
/// - Stripping Arabic diacritics (tashkeel) and tatweel (`ـ`)
/// - Optional stripping of leading `ال` on multi-letter tokens (`الشيخ` -> `شيخ`)
/// - Collapsing whitespace and lowercasing ASCII characters
abstract final class ArabicNameNormalizer {
  static final RegExp _tashkeelAndTatweel = RegExp(
    r'[\u0640\u064B-\u065F\u0670\u06D6-\u06ED]',
  );
  static final RegExp _alefVariants = RegExp(r'[أإآٱ]');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Normalizes Arabic letter variants, removes diacritics/tatweel, lowercases
  /// ASCII, and collapses whitespace — keeping leading `ال` prefixes intact.
  static String normalizeBasic(String input) {
    if (input.isEmpty) return '';
    return input
        .replaceAll(_tashkeelAndTatweel, '')
        .replaceAll(_alefVariants, 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .trim()
        .replaceAll(_whitespace, ' ')
        .toLowerCase();
  }

  /// Full normalization for Arabic/Latin names.
  ///
  /// When [stripAlPrefix] is `true`, strips leading `ال` from any token whose
  /// remaining root is at least 2 characters (`token.length >= 4`) so that
  /// `الحاج أحمد` matches `حاج احمد` and `العربى` matches `عربي`.
  static String normalize(String input, {bool stripAlPrefix = true}) {
    final basic = normalizeBasic(input);
    if (basic.isEmpty || !stripAlPrefix) return basic;

    final tokens = basic.split(' ').map((token) {
      if (token.startsWith('ال') && token.length >= 4) {
        return token.substring(2);
      }
      return token;
    }).where((t) => t.isNotEmpty);

    return tokens.join(' ');
  }

  /// Returns `true` when [a] and [b] represent the same normalized name.
  /// Empty/whitespace-only inputs never match anything.
  static bool areEquivalent(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    return na.isNotEmpty && na == nb;
  }

  /// Returns `true` when [candidate] (or optional [candidatePhone]) matches
  /// [query] under normalized Arabic/Latin rules.
  static bool matchesQuery({
    required String candidate,
    required String query,
    String? candidatePhone,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return true;

    if (candidatePhone != null && candidatePhone.isNotEmpty) {
      if (candidatePhone.toLowerCase().contains(trimmed.toLowerCase())) {
        return true;
      }
      final qDigits = trimmed.replaceAll(RegExp(r'\D'), '');
      if (qDigits.isNotEmpty) {
        final cDigits = candidatePhone.replaceAll(RegExp(r'\D'), '');
        if (cDigits.contains(qDigits)) return true;
      }
    }

    final normQuery = normalize(trimmed);
    final normCandidate = normalize(candidate);
    if (normQuery.isNotEmpty && normCandidate.contains(normQuery)) {
      return true;
    }

    final basicQuery = normalizeBasic(trimmed);
    final basicCandidate = normalizeBasic(candidate);
    return basicQuery.isNotEmpty && basicCandidate.contains(basicQuery);
  }
}
