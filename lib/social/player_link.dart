// Tap-a-player: opens any player's profile from wherever a name or avatar is shown (lobby, rooms, match,
// leaderboards, tournament bracket), plus the unread-DM badge and the server calls the profile uses.
//
// Hook for other screens (e.g. a tournament bracket):
//   PlayerTap(uid: captainId, child: nameWidget)          -> full profile page
//   PlayerTap(uid: uid, sheet: true, child: ...)           -> compact sheet (used in a running match)
//   openPlayer(context, uid)                               -> same, imperatively
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/shell.dart' show AppNav;
import '../core/assets.dart';
import '../core/theme.dart' show fa;
import '../net/auth.dart';
import '../net/supabase.dart';
import '../ui/chrome.dart' show toast;
import 'public_profile.dart' show showPlayerCard;

/// Max length of one direct message (mirrors nx_dm_max_len() on the server).
const int kDmMaxLen = 500;

/// Client-side check before sending a DM; null when ok, else a Persian reason. The server enforces the same rules.
String? dmBodyError(String raw) {
  final b = raw.trim();
  if (b.isEmpty) return 'پیام خالی است';
  if (b.characters.length > kDmMaxLen) return 'پیام خیلی طولانی است (حداکثر ${fa(kDmMaxLen)} حرف)';
  return null;
}

/// True when [uid] is a real other player whose profile can be opened (not a bot / empty seat / me).
bool canOpenPlayer(String? uid, [String? me]) {
  if (uid == null || uid.isEmpty || uid.startsWith('bot')) return false;
  return uid != (me ?? Auth.i.uid);
}

/// Opens [uid]'s profile. [sheet] shows the compact card (keeps the match visible behind it).
void openPlayer(BuildContext context, String? uid, {bool sheet = false}) {
  if (!canOpenPlayer(uid)) return;
  if (sheet) {
    showPlayerSheet(context, uid!);
  } else {
    AppNav.openProfile(uid!);
  }
}

/// Wraps a name / avatar so a tap opens that player's profile. Does nothing for bots, empty seats or yourself.
class PlayerTap extends StatelessWidget {
  final String? uid;
  final Widget child;
  final bool sheet;
  const PlayerTap({super.key, required this.uid, required this.child, this.sheet = false});
  @override
  Widget build(BuildContext context) {
    if (!canOpenPlayer(uid)) return child;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => openPlayer(context, uid, sheet: sheet), child: child);
  }
}

/// Opens (or creates) the DM with [uid] without needing a live BuildContext.
Future<void> startDm(String uid) async {
  try {
    final cid = await rpc('open_dm', {'p_user': uid});
    AppNav.openChat('$cid');
  } catch (e) {
    toast(errFa(e), 'err');
  }
}

// ------------------------------------------------------------------ achievements
class Achievement {
  final String id, title, desc;
  final int progress, target;
  final bool done;
  const Achievement(this.id, this.title, this.desc, this.progress, this.target, this.done);
  factory Achievement.of(Rec r) => Achievement(r.s('id'), r.s('title'), r.s('desc'), r.i('progress'), r.i('target', 1), r.b('done'));
  double get frac => target <= 0 ? 1 : (progress / target).clamp(0, 1).toDouble();
}

List<Achievement> achievementsOf(Object? json) => recs(json).map(Achievement.of).toList();

String achievementIcon(String id) => switch (id) {
  'first_win' || 'wins_10' || 'wins_50' => 'x_medal',
  'played_100' => 'x_ball',
  'goals_50' || 'goals_200' => 'x_statue',
  'streak_5' || 'level_10' || 'level_25' => 'x_star',
  'arena_100' => 'x_crown',
  'champion' => 'x_trophy',
  'followers_10' => 'x_player',
  _ => 'x_medal',
};

// ------------------------------------------------------------------ server calls
class SocialApi {
  static Future<Rec> card(String uid) async => Rec.of(await rpc('player_card', {'p_user': uid}));
  static Future<Rec> follow(String uid) async => Rec.of(await rpc('follow_user', {'p_user': uid}));
  static Future<Rec> unfollow(String uid) async => Rec.of(await rpc('unfollow_user', {'p_user': uid}));
  static Future<void> block(String uid) async => rpc('block_user', {'p_user': uid});
  static Future<void> unblock(String uid) async => rpc('unblock_user', {'p_user': uid});
  static Future<void> markRead(String conv) async {
    try {
      await rpc('mark_conversation_read', {'p_conv': conv});
    } catch (_) {}
    DmUnread.i.refreshSoon();
  }
}

// ------------------------------------------------------------------ unread badge
/// Unread direct messages. Realtime on `messages` (the app already uses Realtime) with a light 90 s poll as backup.
class DmUnread {
  DmUnread._();
  static final DmUnread i = DmUnread._();
  final ValueNotifier<int> count = ValueNotifier<int>(0);
  RealtimeChannel? _ch;
  Timer? _poll, _debounce;
  String? _uid;

  /// Idempotent; call whenever a badge is shown. Re-binds when the signed-in user changes.
  void ensure() {
    if (!supaReady) return;
    final u = Auth.i.uid;
    if (u == _uid && (_ch != null || u == null)) return;
    _stop();
    _uid = u;
    if (u == null) {
      count.value = 0;
      return;
    }
    try {
      _ch = sb
          .channel('dm-unread:$u')
          .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', callback: (_) => refreshSoon())
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'conversation_members',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u),
            callback: (_) => refreshSoon(),
          )
          .subscribe();
    } catch (_) {}
    _poll = Timer.periodic(const Duration(seconds: 90), (_) => refresh());
    refresh();
  }

  void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), refresh);
  }

  Future<void> refresh() async {
    if (!supaReady || Auth.i.uid == null) return;
    try {
      final n = await rpc('dm_unread_total');
      count.value = n is num ? n.toInt() : int.tryParse('$n') ?? 0;
    } catch (_) {}
  }

  void _stop() {
    _poll?.cancel();
    _debounce?.cancel();
    final c = _ch;
    _ch = null;
    if (c != null) {
      try {
        sb.removeChannel(c);
      } catch (_) {}
    }
  }
}

/// Small red count bubble for the messages entry; hidden at zero.
class UnreadBadge extends StatelessWidget {
  final Widget child;
  const UnreadBadge({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    DmUnread.i.ensure();
    return ValueListenableBuilder<int>(
      valueListenable: DmUnread.i.count,
      builder: (_, n, ch) => Stack(clipBehavior: Clip.none, children: [
        ch!,
        if (n > 0)
          Positioned(
            top: -4,
            left: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xffff4d6d), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xff0b1236), width: 2)),
              child: Text(n > 99 ? '+۹۹' : fa(n), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'Vazirmatn')),
            ),
          ),
      ]),
      child: child,
    );
  }
}

/// Compact profile card (bottom sheet) with Follow / Message / full profile.
Future<void> showPlayerSheet(BuildContext context, String uid) => showPlayerCard(context, uid);

String achIcon(String id) => ui2(achievementIcon(id));
