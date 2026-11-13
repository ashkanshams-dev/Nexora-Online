// Disc catalog (gem prices + power/accuracy) and the signed-in user's inventory — port of src/net/discs.tsx.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../game/data.dart';
import '../game/discs_v11.dart';
import '../game/engine.dart' show DiscStats;
import '../ui/theme.dart' show fa;
import 'auth.dart';
import 'supabase.dart';

const _KEY = 'nexora.discs.v1';
Map<String, JRow> _catalog = {};

DiscStats _fallback(String id) {
  final t = TEAMS.where((x) => x.id == id).firstOrNull;
  final base = t?.cat == 'leg' || t?.cat == 'vip' ? 8.0 : (t?.cat == 'club' || t?.cat == 'nat' || t?.cat == 'iran') ? 5.0 : 6.0;
  return DiscStats(base, base);
}

DiscStats discStats([String? id]) {
  final d = id != null ? _catalog[id] : null;
  return d != null ? DiscStats((d['power'] as num).toDouble(), (d['accuracy'] as num).toDouble()) : _fallback(id ?? 'club0');
}

int discPrice(String id) => ri(_catalog[id], 'price_gems');
bool isFreeDisc(String id) {
  final c = _catalog[id];
  if (c != null) return ri(c, 'price_gems') == 0;
  if (RegExp(r'^(club|nat)\d+$').hasMatch(id)) return true;
  final cat = RegExp(r'^[a-z]+').stringMatch(id) ?? '';
  return CATS_V11.any((c) => c.$1 == cat) && !PAID_V11.contains(cat);
}

class Discs extends ChangeNotifier {
  Discs._();
  static final Discs I = Discs._();
  Map<String, JRow> get catalog => _catalog;
  bool get loaded => _catalog.isNotEmpty;
  Set<String> owned = {};
  RealtimeChannel? _ch;
  String? _uid;

  String? get equipped => Auth.I.profile?['equipped_disc'] as String?;

  Future<void> init() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_KEY);
      if (s != null && _catalog.isEmpty) _catalog = (jsonDecode(s) as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
    } catch (_) {}
    notifyListeners();
    Auth.I.addListener(_onAuth);
    await _loadCatalog();
    _onAuth();
  }

  Future<void> _loadCatalog() async {
    if (!ONLINE_CONFIGURED) return;
    try {
      final data = await supabase.from('discs').select();
      if (data.isEmpty) return;
      _catalog = {for (final d in data) d['id'] as String: d};
      notifyListeners();
      (await SharedPreferences.getInstance()).setString(_KEY, jsonEncode(_catalog));
    } catch (_) {}
  }

  void _onAuth() {
    final uid = Auth.I.uid;
    if (uid == _uid) return;
    _uid = uid;
    if (_ch != null) supabase.removeChannel(_ch!);
    _ch = null;
    if (uid == null) {
      owned = {};
      notifyListeners();
      return;
    }
    _loadCatalog();
    Future<void> load() async {
      try {
        final d = await supabase.from('inventory').select('disc_id').eq('user_id', uid);
        owned = {for (final r in d) r['disc_id'] as String};
        notifyListeners();
      } catch (_) {}
    }

    load();
    _ch = supabase
        .channel('inv:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => load(),
        )
        .subscribe();
  }

  bool has(String id) => isFreeDisc(id) || owned.contains(id);

  Future<({bool ok, String? error})> buy(String id) async {
    try {
      await rpc('buy_disc', {'p_disc': id});
      owned = {...owned, id};
      notifyListeners();
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: errFa(e));
    }
  }

  Future<({bool ok, String? error})> equip(String id) async {
    try {
      await rpc('equip_disc', {'p_disc': id});
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: errFa(e));
    }
  }

  /// buy (if needed) + equip with the full online flow; true when equipped
  Future<bool> buyAndEquip(String id, String name, void Function(String m, [String k]) toast) async {
    final auth = Auth.I;
    if (auth.uid == null) {
      final u = await auth.ensure().catchError((_) => null);
      if (u == null) {
        toast('برای خرید دیسک باید آنلاین باشی', 'err');
        return false;
      }
    }
    if (!has(id)) {
      final price = ri(_catalog[id], 'price_gems'), g = ri(auth.profile, 'gems');
      if (auth.profile != null && g < price) {
        toast('${fa(price - g)} الماس کم داری · چالش‌ها، فصل و تورنمنت‌ها الماس می‌دهند', 'err');
        return false;
      }
      final r = await buy(id);
      if (!r.ok) {
        toast(r.error!, 'err');
        return false;
      }
      toast('$name باز شد!', 'ok');
    }
    final e = await equip(id);
    if (!e.ok) {
      toast(e.error!, 'err');
      return false;
    }
    return true;
  }
}
