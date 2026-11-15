// Cups: in-app alerts for tournament notifications (15-minute reminders, check-in, draw, "your match is ready",
// prizes). The server writes rows into public.notifications (supabase/cups.sql); this listens to the signed-in
// user's inserts over realtime and shows a card with sound + vibration, or a toast for minor news.
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'cups.dart';

class CupAlerts {
  CupAlerts._();
  static final i = CupAlerts._();

  /// Opens the online area on a cup page (`cup:<id>`); wired by main.dart to the app shell.
  void Function(String entry)? open;
  RealtimeChannel? _ch;
  String? _uid;
  bool _showing = false;

  void init() {
    Auth.i.addListener(_sync);
    _sync();
  }

  void _sync() {
    final u = Auth.i.uid;
    if (u == _uid) return;
    if (_ch != null) {
      sb.removeChannel(_ch!);
      _ch = null;
    }
    _uid = u;
    if (u == null || !supaReady) return;
    _ch = sb
        .channel('cupalerts:$u')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u),
            callback: (p) => handle(p.newRecord))
        .subscribe();
  }

  /// Big card for what needs the player now; a toast for the rest.
  static const urgent = {'cup_ready', 'cup_soon', 'cup_match_soon', 'cup_draw', 'cup_promoted'};

  void handle(Map<String, dynamic> n) {
    final kind = '${n['kind'] ?? ''}';
    if (!kind.startsWith('cup_')) return;
    final data = n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
    final cup = '${data['cup'] ?? ''}';
    final title = '${n['title'] ?? ''}', body = n['body']?.toString();
    // the cup page / cup room already on screen handles it itself
    if (CupUi.inCupRoom || (cup.isNotEmpty && CupUi.openCup == cup)) return;
    final ctx = navKey.currentContext;
    if (!urgent.contains(kind) || ctx == null || _showing || cup.isEmpty) {
      toast(title, kind == 'cup_out' || kind == 'cup_cancel' ? 'err' : 'ok');
      return;
    }
    sfx(kind == 'cup_ready' ? Snd.whistle : Snd.ready);
    buzz('heavy');
    _showing = true;
    showCard(ctx, accent: kind == 'cup_ready' ? C.red : C.orange, child: (cc) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tTitle(title, size: 17, align: TextAlign.center),
            if (body != null && body.isNotEmpty) ...[const SizedBox(height: 6), T(body, size: 12, color: C.dim, align: TextAlign.center)],
            const SizedBox(height: 14),
            Btn(kind == 'cup_ready' ? 'ورود به مسابقه' : 'رفتن به تورنمنت', colors: kind == 'cup_ready' ? G.red : G.gold, onTap: () {
              Navigator.pop(cc);
              open?.call('cup:$cup');
            }),
            const SizedBox(height: 8),
            Btn('بعداً', small: true, colors: G.dark, onTap: () => Navigator.pop(cc)),
          ]),
        )).whenComplete(() => _showing = false);
  }
}
