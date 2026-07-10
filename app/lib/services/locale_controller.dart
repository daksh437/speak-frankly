import 'package:flutter/material.dart';

/// Holds the app's current UI locale, derived from the learner's chosen native
/// language. Null → fall back to the device locale / English. Localized:
/// Hindi, Spanish, French, Portuguese; others fall back to English.
class LocaleController {
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  static const _map = {
    'Hindi': 'hi',
    'Spanish': 'es',
    'French': 'fr',
    'Portuguese': 'pt',
  };

  static Locale? localeFor(String languageName) {
    final code = _map[languageName];
    return code == null ? null : Locale(code);
  }

  static void setFromLanguage(String languageName) {
    locale.value = localeFor(languageName);
  }
}
