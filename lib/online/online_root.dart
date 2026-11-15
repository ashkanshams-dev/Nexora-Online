// Port of src/online/OnlineRoot.tsx: navigator for the online area (hub -> lobby -> match -> result, plus
// tournaments, ranks/leagues, arena, challenges). Owns the RoomLink of the joined room.
import 'package:material_ui/material_ui.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'competitive.dart';
import 'cups.dart';
import 'link.dart';
import 'lobby.dart';
import 'online_match.dart';
import 'rematch.dart';
import 'room_v6.dart';

class _R {
  final String k;
  final String? id, tab;
  final OnlineOutcome? o;
  final Rec? before;
  const _R(this.k, {this.id, this.tab, this.o, this.before});
}

class OnlineRoot extends StatefulWidget {
  final String entry;
  final String? quick;

  /// v0.6: a room joined / created from the main screen's room list -> straight into the room; leaving it closes
  /// the online page again (back to the main screen).
  final Rec? room;
  const OnlineRoot({super.key, this.entry = 'hub', this.quick, this.room});
  @override
  State<OnlineRoot> createState() => _OnlineRootState();
}

class _OnlineRootState extends State<OnlineRoot> {
  late List<_R> stack = widget.entry.startsWith('cup:')
      ? [const _R('tours'), _R('cup', id: widget.entry.substring(4))]
      : [widget.entry == 'leagues' ? const _R('ranks', tab: 'leagues') : _R(widget.entry)];
  RoomLink? link;
  String? connErr, skip;
  bool firstLoad = true, quickDone = false, _directDone = false;
  Rec? before;

  _R get top => stack.last;

  @override
  void initState() {
    super.initState();
    connect();
  }

  void connect() {
    setState(() => connErr = null);
    Auth.i.ensure().then((id) {
      if (id == null && mounted) setState(() => connErr = 'اتصال به سرور برقرار نشد');
      if (id != null) _maybeQuick();
      if (id != null && widget.room != null && !_directDone) {
        _directDone = true;
        enterRoom(widget.room!);
      }
      if (mounted) setState(() {});
    }, onError: (e) => mounted ? setState(() => connErr = errFa(e)) : null);
  }

  void _maybeQuick() {
    final q = widget.quick;
    if (q == null || quickDone) return;
    quickDone = true;
    Oracle.i.react('search');
    rpc('quick_match', {'p_mode': q, 'p_kind': 'quick'}).then((r) => enterRoom(Rec.of(r)), onError: (e) => toast(errFa(e), 'err'));
  }

  @override
  void dispose() {
    final l = link;
    if (l != null) {
      rpc('leave_room', {'p_room': l.id}).catchError((_) => null);
      l.removeListener(_onLink);
      l.dispose();
    }
    Sound.scene(AudioScene.menu);
    super.dispose();
  }

  void _setScene() => Sound.scene(top.k == 'match' ? AudioScene.match : top.k == 'lobby' || top.k == 'result' ? AudioScene.room : AudioScene.menu);

  void _set(List<_R> s) {
    setState(() => stack = s.isEmpty ? [const _R('hub')] : s);
    _setScene();
  }

  void push(_R r) => _set([...stack, r]);
  void pop() => stack.length > 1 ? _set(stack.sublist(0, stack.length - 1)) : null;
  List<_R> get _noRoom => stack.where((x) => x.k != 'lobby' && x.k != 'match' && x.k != 'result').toList();

  void enterRoom(Rec room) {
    final uid = Auth.i.uid;
    if (uid == null) return;
    if (link != null && link!.id == room.s('id')) {
      _set([..._noRoom, const _R('lobby')]);
      return;
    }
    _dropLink();
    firstLoad = true;
    skip = null;
    final l = RoomLink(room.s('id'), uid, Auth.i.profile?.s('username') ?? 'Pilot')..addListener(_onLink);
    link = l;
    _set([..._noRoom, const _R('lobby')]);
  }

  void _dropLink() {
    final l = link;
    link = null;
    if (l != null) {
      l.removeListener(_onLink);
      l.dispose();
    }
  }

  Future<void> leaveRoom() async {
    final l = link;
    if (l != null) {
      try {
        await rpc('leave_room', {'p_room': l.id});
      } catch (_) {}
    }
    _dropLink();
    if (widget.room != null && _noRoom.length <= 1 && mounted) {
      Navigator.pop(context);
      return;
    }
    _set(_noRoom);
    Sound.playLoop(Snd.music);
  }

  void _onLink() {
    final l = link;
    if (l == null || !l.loaded || !mounted) return;
    final room = l.room;
    if (l.gone) {
      if (top.k == 'lobby' || top.k == 'result') {
        toast(room != null ? 'از اتاق خارج شدی' : 'اتاق بسته شد', 'err');
        _dropLink();
        _set(_noRoom);
      }
      return;
    }
    if (room == null) return;
    if (firstLoad) {
      firstLoad = false;
      if (room.s('status') == 'playing' && room.str('current_match') != null && room.s('host') == l.me) {
        skip = room.s('current_match');
        rpc('abandon_match', {'p_match': skip}).then((_) => l.ping(), onError: (_) => null);
        return;
      }
    }
    // v9 rematch: a seated player still on the result screen follows the room into its next match (RematchBar)
    final cur = room.str('current_match');
    final rematch = top.k == 'result' && cur != top.o?.matchId && l.players.any((p) => p.s('user_id') == l.me && p.s('role') == 'player');
    if ((top.k == 'lobby' || rematch) && room.s('status') == 'playing' && cur != null && cur != skip) {
      before = Auth.i.profile;
      if (rematch) {
        _set([...stack.sublist(0, stack.length - 1), _R('match', id: cur)]);
      } else {
        push(_R('match', id: cur));
      }
    }
  }

  Future<void> back() async {
    if (top.k == 'lobby') {
      if (await confirm(context, 'خروج از اتاق؟', 'جایگاهت در اتاق آزاد می‌شود.', yes: 'خروج', no: 'ماندن')) leaveRoom();
      return;
    }
    if (top.k == 'result') return _set([...stack.sublist(0, stack.length - 1), const _R('lobby')]);
    if (stack.length > 1) return pop();
    if (link != null) await leaveRoom();
    if (mounted) Navigator.pop(context);
  }

  void nav(String n) => push(_R(n));

  /// v9: the online result screen with the rematch bar under it (nothing for spectators / tournament rooms).
  Widget _withRematch(RoomLink? l, Widget result) =>
      l == null ? result : ColoredBox(color: C.bg, child: Column(children: [Expanded(child: result), RematchBar(link: l)]));

  @override
  Widget build(BuildContext context) {
    if (Auth.i.uid == null) {
      return Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          const Space(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (connErr != null) ErrorState(connErr!, onRetry: connect) else ...[const Spinner(size: 40), const SizedBox(height: 12), const T('در حال اتصال به سرور…', size: 14, color: C.dim)],
                const SizedBox(height: 16),
                SizedBox(width: 160, child: Btn('بازگشت', small: true, colors: G.dark, onTap: () => Navigator.pop(context))),
              ]),
            ),
          ),
        ]),
      );
    }
    final t = top, l = link;
    final Widget page = switch (t.k) {
      'lobby' when l != null && isCupRoom(l.room) => CupLobby(link: l, onLeave: leaveRoom),
      'lobby' when l != null => RoomScreen(link: l, onLeave: back, settings: (_, lk) => RoomSettingsSheet(link: lk), onWatch: () {
          final m = l.room?.str('current_match');
          if (m != null) push(_R('match', id: m));
        }),
      'match' when l != null => OnlineMatchScreen(
          key: ValueKey('m${t.id}'),
          link: l,
          matchId: t.id!,
          onFinish: (o) => _set([...stack.sublist(0, stack.length - 1), _R('result', o: o, before: before)]),
          onExit: (why) {
            skip = t.id;
            _set([...stack.sublist(0, stack.length - 1), const _R('lobby')]);
          }),
      'result' when isCupRoom(l?.room) => OnlineResultScreen(o: t.o!, before: t.before, onLobby: () => _set([...stack.sublist(0, stack.length - 1), const _R('lobby')]), onLeave: leaveRoom),
      'result' => _withRematch(l, OnlineResultScreen(o: t.o!, before: t.before, onLobby: () => _set([...stack.sublist(0, stack.length - 1), const _R('lobby')]), onLeave: leaveRoom)),
      'tours' => CupsScreen(onBack: back, onOpen: (id) => push(_R('cup', id: id))),
      'cup' => CupScreen(key: ValueKey('c${t.id}'), id: t.id!, onBack: back, onRoom: enterRoom),
      'tour' => TourScreen(key: ValueKey('t${t.id}'), id: t.id!, onBack: back, onRoom: enterRoom),
      'ranks' => RanksScreen(onBack: back, tab: t.tab ?? 'top'),
      'arena' => ArenaScreen(onBack: back, onRoom: enterRoom),
      'challenges' => ChallengesScreen(onBack: back),
      _ => HubScreen(onBack: back, onRoom: enterRoom, onNav: nav),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did && t.k != 'match') back();
      },
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey('${t.k}${t.id ?? ''}${stack.length}'), child: page)),
    );
  }
}
