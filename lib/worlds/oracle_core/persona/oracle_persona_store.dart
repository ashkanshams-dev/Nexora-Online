/// Loads the admin-editable ORACLE persona config (Supabase `nx_oracle_persona`, cached locally) into
/// [OraclePersona.instance], and keeps per-device tutorial view counts.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/storage/local_store.dart';
import 'oracle_persona.dart';

class OraclePersonaStore {
  OraclePersonaStore._();

  static const String _kCfg = 'oracle_persona.cfg';
  static const String _kViews = 'oracle_persona.tut_views';
  static bool _loadedCache = false;
  static DateTime? _fetchedAt;

  /// Applies the locally cached admin config (instant, offline).
  static void loadCached() {
    if (_loadedCache) return;
    _loadedCache = true;
    try {
      final String? raw = LocalStore.instance.getString(_kCfg);
      if (raw != null && raw.isNotEmpty) {
        final Object? j = jsonDecode(raw);
        if (j is Map) OraclePersona.instance.applyConfig(Map<String, dynamic>.from(j));
      }
    } catch (_) {/* keep defaults */}
  }

  /// Fetches the admin config from Supabase (at most every 10 minutes) and caches it.
  static Future<void> refresh(SupabaseClient? c, {bool force = false}) async {
    loadCached();
    if (c == null) return;
    if (!force && _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 10)) return;
    _fetchedAt = DateTime.now();
    try {
      final Map<String, dynamic>? row =
          await c.from('nx_oracle_persona').select('data').eq('id', 1).maybeSingle().timeout(const Duration(seconds: 12));
      final Object? d = row?['data'];
      if (d is Map && d.isNotEmpty) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(d);
        OraclePersona.instance.applyConfig(m);
        await LocalStore.instance.setString(_kCfg, jsonEncode(m));
      }
    } catch (_) {/* offline or table missing → cached/defaults */}
  }

  /// Saves a new config (admins only; enforced server-side by `nx_oracle_persona_save`).
  static Future<String?> save(SupabaseClient c, Map<String, dynamic> data) async {
    try {
      await c.rpc('nx_oracle_persona_save', params: <String, dynamic>{'p_data': data});
      OraclePersona.instance.applyConfig(data);
      await LocalStore.instance.setString(_kCfg, jsonEncode(data));
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Map<String, int> tutorialViews() {
    try {
      final String? raw = LocalStore.instance.getString(_kViews);
      if (raw == null) return <String, int>{};
      final Object? j = jsonDecode(raw);
      return j is Map ? j.map((dynamic k, dynamic v) => MapEntry<String, int>('$k', (v as num?)?.toInt() ?? 0)) : <String, int>{};
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> markTutorial(OracleTutorial t) async {
    final Map<String, int> v = tutorialViews();
    v[t.key] = (v[t.key] ?? 0) + 1;
    await LocalStore.instance.setString(_kViews, jsonEncode(v));
  }
}
