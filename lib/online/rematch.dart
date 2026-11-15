// v9 online rematch ("بازی دوباره") on the online result screen.
//
// No new wire messages: the request IS the server's ready flag (set_ready). report_match puts the room back to
// 'waiting' and clears every ready flag, so after a match "ready = true" means "I want to play again". When every
// seated player of the room is ready the host calls start_match (in matchmade rooms, where any seated player may
// start, the others retry after a short grace period; the server serialises the race). OnlineRoot then opens the
// new match for everyone still on the result screen: same room, same opponent, same settings.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../net/supabase.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'link.dart';

enum Rematch { off, wait, idle, asked, offered, starting, oppLeft }

/// Pure state of the rematch for [me] (tested in test/rematch_test.dart).
Rematch rematchState(Rec? room, List<Rec> players, String me) {
  if (room == null || room.str('tournament_match_id') != null) return Rematch.off;
  final seated = players.where((p) => p.s('role') == 'player' && (p.i('team', -1) == 0 || p.i('team', -1) == 1)).toList();
  final mine = seated.where((p) => p.s('user_id') == me).firstOrNull;
  if (mine == null) return Rematch.off; // spectators don't vote
  final opps = seated.where((p) => p.s('user_id') != me).toList();
  if (opps.isEmpty) return Rematch.oppLeft;
  if (room.s('status') != 'waiting') return Rematch.wait; // result not on the server yet
  final meR = mine.b('ready'), oppR = opps.every((p) => p.b('ready'));
  return meR && oppR ? Rematch.starting : meR ? Rematch.asked : oppR ? Rematch.offered : Rematch.idle;
}

/// Who calls start_match once everyone accepted: the host at once; in matchmade rooms (any seated player may
/// start) the others after [grace] as a fallback when the host is gone or slow.
bool rematchStarter({required bool isHost, required String kind, required Duration waited, Duration grace = const Duration(seconds: 4)}) =>
    isHost || ((kind == 'quick' || kind == 'arena' || kind == 'duel') && waited >= grace);

class RematchBar extends StatefulWidget {
  final RoomLink link;
  const RematchBar({super.key, required this.link});
  @override
  State<RematchBar> createState() => _RematchBarState();
}

class _RematchBarState extends State<RematchBar> {
  RoomLink get link => widget.link;
  bool busy = false;
  Rematch last = Rematch.off;
  DateTime? _since;
  Timer? _retry;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    link.addListener(_onLink);
  }

  @override
  void dispose() {
    link.removeListener(_onLink);
    _retry?.cancel();
    super.dispose();
  }

  Rematch get st => rematchState(link.room, link.players, link.me);

  void _onLink() {
    if (!mounted) return;
    final s = st;
    if (s == Rematch.offered && last != Rematch.offered) sfx(Snd.ready);
    if (s == Rematch.starting) {
      _since ??= DateTime.now();
      _maybeStart();
      _retry ??= Timer.periodic(const Duration(seconds: 2), (_) => _maybeStart());
    } else {
      _since = null;
      _retry?.cancel();
      _retry = null;
    }
    last = s;
    setState(() {});
  }

  void _maybeStart() {
    final room = link.room;
    if (room == null || _started || st != Rematch.starting) return;
    final ok = rematchStarter(isHost: room.s('host') == link.me, kind: room.s('kind', 'casual'), waited: DateTime.now().difference(_since ?? DateTime.now()));
    if (!ok) return;
    _started = true;
    rpc('start_match', {'p_room': room.s('id')}).then((_) => link.ping(), onError: (_) => _started = false);
  }

  Future<void> _set(bool v) async {
    final room = link.room;
    if (room == null || busy) return;
    setState(() => busy = true);
    try {
      await rpc('set_ready', {'p_room': room.s('id'), 'p_ready': v});
      link.ping();
    } catch (e) {
      toast(errFa(e), 'err');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = st;
    if (s == Rematch.off) return const SizedBox.shrink();
    final (String label, String? note, bool on, bool want, List<Color> col) = switch (s) {
      Rematch.wait => ('بازی دوباره', 'در حال ثبت نتیجه…', false, true, G.primary),
      Rematch.idle => ('بازی دوباره', null, true, true, G.primary),
      Rematch.asked => ('لغو درخواست', 'منتظر جواب حریف…', true, false, G.dark),
      Rematch.offered => ('قبول بازی دوباره', 'حریف می‌خواهد دوباره بازی کنید!', true, true, G.gold),
      Rematch.starting => ('بازی دوباره', 'هر دو آماده‌اید؛ شروع بازی…', false, true, G.gold),
      Rematch.oppLeft => ('بازی دوباره', 'حریف از اتاق رفته است', false, true, G.dark),
      Rematch.off => ('', null, false, true, G.dark),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.paddingOf(context).bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (note != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: T(note, size: 12, color: s == Rematch.offered ? C.gold : C.dim, align: TextAlign.center)),
        Btn(busy ? '…' : label, colors: col, disabled: !on || busy, onTap: () => _set(want)),
      ]),
    );
  }
}
