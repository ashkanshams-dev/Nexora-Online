// Port of src/net/discs.tsx: disc catalog (gem prices + power/accuracy), cached on disk, and the user's inventory.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../ui/chrome.dart';
import '../core/owned.dart' show kUnlockAllShop;
import 'auth.dart';
import 'supabase.dart';

class DiscRow {
  final String id, cat, name;
  final int priceGems;
  final double power, accuracy;
  DiscRow(this.id, this.cat, this.name, this.priceGems, this.power, this.accuracy);
  factory DiscRow.of(Rec r) => DiscRow(r.s('id'), r.s('cat'), r.s('name'), r.i('price_gems'), r.d('power', 5), r.d('accuracy', 5));
  Map<String, dynamic> toJson() => {'id': id, 'cat': cat, 'name': name, 'price_gems': priceGems, 'power': power, 'accuracy': accuracy};
}

DiscStats _fallback(String id) {
  final (pw, ac) = teamStatsFor(id);
  return DiscStats(pw, ac);
}

class Discs extends ChangeNotifier {
  Discs._();
  static final Discs i = Discs._();
  static const _key = 'nexora.discs.v1';
  Map<String, DiscRow> catalog = {};
  Set<String> owned = {};
  RealtimeChannel? _ch;
  String? _for;

  bool get loaded => catalog.isNotEmpty;

  // v5: the server's disc ids do NOT line up with the app's team ids (server club0 = Barcelona, app club0 = Real
  // Madrid; the server has no elite/vip/emb/leg/chrome/spt rows). Rows are matched to a team by category + name.
  Map<String, DiscRow> _byName = {};
  Map<String, DiscRow>? _byNameFor;
  static String _norm(String n) => n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  DiscRow? rowFor(String? localId) {
    if (localId == null) return null;
    if (!identical(_byNameFor, catalog)) {
      _byNameFor = catalog;
      _byName = {};
      for (final r in catalog.values) {
        _byName.putIfAbsent('${r.cat}|${_norm(r.name)}', () => r);
      }
    }
    final t = kTeams.where((t) => t.id == localId).firstOrNull;
    if (t == null) return catalog[localId]; // a server id (equipped_disc of a non-Flutter peer)
    return _byName['${t.cat}|${_norm(t.name)}'];
  }

  /// the server id of a local team (for equip/buy), or null when the server does not sell it
  String? serverId(String localId) => rowFor(localId)?.id;
  String? get equipped => Auth.i.profile?.str('equipped_disc');

  DiscStats stats(String? id) {
    final d = rowFor(id);
    return d != null ? DiscStats(d.power, d.accuracy) : _fallback(id ?? 'club0');
  }

  int price(String id) => rowFor(id)?.priceGems ?? 0;
  bool isFree(String id) {
    final r = rowFor(id);
    return r != null ? r.priceGems == 0 : RegExp(r'^(club|nat)\d+$').hasMatch(id);
  }

  bool has(String id) => kUnlockAllShop || isFree(id) || owned.contains(serverId(id) ?? id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s != null && catalog.isEmpty) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        catalog = m.map((k, v) => MapEntry(k, DiscRow.of(Rec.of(v))));
        notifyListeners();
      } catch (_) {}
    }
    if (supaReady) {
      sb.from('discs').select().then((data) {
        final rows = recs(data);
        if (rows.isEmpty) return;
        catalog = {for (final r in rows) r.s('id'): DiscRow.of(r)};
        prefs.setString(_key, jsonEncode(catalog.map((k, v) => MapEntry(k, v.toJson()))));
        notifyListeners();
      }).catchError((_) {});
    }
    Auth.i.addListener(_onAuth);
    _onAuth();
  }

  void _onAuth() {
    final uid = Auth.i.uid;
    if (uid == _for) return;
    _for = uid;
    if (_ch != null) {
      sb.removeChannel(_ch!);
      _ch = null;
    }
    owned = {};
    if (uid == null) {
      notifyListeners();
      return;
    }
    void load() => sb.from('inventory').select('disc_id').eq('user_id', uid).then((data) {
          owned = {for (final r in recs(data)) r.s('disc_id')};
          notifyListeners();
        }).catchError((_) {});
    load();
    _ch = sb
        .channel('inv:$uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (_) => load())
        .subscribe();
  }

  Future<(bool, String?, int?)> buy(String id) async {
    try {
      final sid = serverId(id) ?? id;
      final g = await rpc('buy_disc', {'p_disc': sid});
      owned = {...owned, sid};
      notifyListeners();
      return (true, null, g is num ? g.toInt() : null);
    } catch (e) {
      return (false, errFa(e), null);
    }
  }

  /// Server-side equip. With kUnlockAllShop the selection is LOCAL (Store.p.team, sent to peers in presence 'tm'):
  /// the server equip RPC is only called for discs the account really owns, and a 'not owned' reply is a soft
  /// failure (the local selection stays) - the server would otherwise reject every unlocked-for-testing disc.
  Future<(bool, String?)> equip(String id) async {
    final sid = serverId(id);
    if (sid == null) return (true, null); // not sold by the server: local-only selection
    final serverOwned = isFree(id) || owned.contains(sid);
    if (kUnlockAllShop && !serverOwned) return (true, null);
    try {
      await rpc('equip_disc', {'p_disc': sid});
      return (true, null);
    } catch (e) {
      if (kUnlockAllShop || e.toString().toLowerCase().contains('not owned')) return (true, null);
      return (false, errFa(e));
    }
  }

  /// buy (if needed) + equip with the full online flow; true when equipped (useBuyDisc in RN)
  Future<bool> buyAndEquip(String id, String name, {void Function(String id)? onEquipped}) async {
    if (Auth.i.uid == null) {
      final u = await Auth.i.ensure().catchError((_) => null);
      if (u == null) {
        toast('برای خرید دیسک باید آنلاین باشی', 'err');
        return false;
      }
    }
    if (!has(id)) {
      final pr = price(id), g = Auth.i.profile?.i('gems') ?? 0;
      if (Auth.i.profile != null && g < pr) {
        toast('${fa(pr - g)} الماس کم داری · چالش‌ها، فصل و تورنمنت‌ها الماس می‌دهند', 'err');
        return false;
      }
      final r = await buy(id);
      if (!r.$1) {
        toast(r.$2!, 'err');
        return false;
      }
      toast('$name باز شد!', 'ok');
    }
    final e = await equip(id);
    if (!e.$1) {
      toast(e.$2!, 'err');
      return false;
    }
    onEquipped?.call(id);
    return true;
  }
}
