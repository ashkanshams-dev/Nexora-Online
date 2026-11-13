// Bilingual UI (fa / en) — port of src/i18n/index.ts. Every Persian literal is the lookup key; tr()
// translates at render time so screens keep their Persian source text (identical en.json).
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

enum Lang { fa, en }

Lang LANG = Lang.fa;
Map<String, String> _dict = {};
List<(RegExp, String)> _pats = [];
final Map<String, String> _cache = {};
final RegExp _fa = RegExp(r'[\u0600-\u06FF]');
final RegExp _faDigit = RegExp(r'[۰-۹]');

Future<void> loadI18n() async {
  final raw = await rootBundle.loadString('lib/i18n/en.json');
  _dict = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
  String esc(String s) => s.replaceAllMapped(RegExp(r'[.*+?^$()|[\]\\{}]'), (m) => '\\${m[0]}');
  _pats = _dict.keys.where((k) => k.contains('{}')).map((k) {
    final re = '^${k.split('{}').map(esc).join(r'([\s\S]*?)')}\$';
    return (RegExp(re), _dict[k]!);
  }).toList()
    ..sort((a, b) => b.$1.pattern.length.compareTo(a.$1.pattern.length));
}

void setLang(Lang l) {
  LANG = l;
  _cache.clear();
}

bool isEn() => LANG == Lang.en;

String _latin(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = fa.indexOf(ch), j = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch == '٬' ? ',' : ch == '٫' ? '.' : ch);
  }
  return b.toString();
}

String _look(String s) {
  final hit = _dict[s];
  if (hit != null) return hit;
  for (final (re, en) in _pats) {
    final m = re.firstMatch(s);
    if (m == null) continue;
    var i = 1;
    return en.replaceAllMapped('{}', (_) => _look(m.group(i++) ?? ''));
  }
  if (s.contains('\n')) return s.split('\n').map(_look).join('\n');
  return s;
}

/// translate a UI string for the current language (identity in Persian)
String tr(String s) {
  if (LANG == Lang.fa || s.isEmpty || (!_fa.hasMatch(s) && !_faDigit.hasMatch(s))) return s;
  final c = _cache[s];
  if (c != null) return c;
  final r = _latin(_look(s));
  if (_cache.length > 4000) _cache.clear();
  _cache[s] = r;
  return r;
}
