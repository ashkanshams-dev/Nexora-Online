// Device-level UI preferences (theme + language) — port of src/prefs.ts. Same storage key.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'i18n/i18n.dart';
import 'ui/theme.dart';

const _KEY = 'nexora.ui.v1';
ThemeName uiTheme = ThemeName.dark;

Future<void> loadPrefs() async {
  try {
    final s = (await SharedPreferences.getInstance()).getString(_KEY);
    if (s != null) {
      final j = jsonDecode(s) as Map;
      uiTheme = j['theme'] == 'light' ? ThemeName.light : ThemeName.dark;
      setLang(j['lang'] == 'en' ? Lang.en : Lang.fa);
    }
  } catch (_) {}
  applyTheme(uiTheme);
}

/// persists; the app shell rebuilds from the root (RN reloaded the bundle)
Future<void> setUiPref({ThemeName? theme, Lang? lang}) async {
  if (theme != null) uiTheme = theme;
  if (lang != null) setLang(lang);
  await (await SharedPreferences.getInstance())
      .setString(_KEY, jsonEncode({'theme': uiTheme.name, 'lang': LANG.name}));
}
