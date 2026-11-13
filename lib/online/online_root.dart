// Online navigator — port of src/online/OnlineRoot.tsx: hub → lobby → match → result, plus tournaments, ranks, arena,
// challenges. One RoomLink per joined room; room state drives navigation; matchmaking queue overlay lives here so it
// follows the player across hub / arena.
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/space.dart';
import '../ui/theme.dart';
import 'challenges.dart';
import 'hub.dart';
import 'link.dart';
import 'lobby.dart';
import 'matchmaker.dart';
import 'online_match.dart';
import 'online_result.dart';
import 'ranks.dart';
import 'tournaments.dart';
import 'ui.dart';

sealed class R {
  const R();
  String get k;
}

class RHub extends R {
  const RHub();
  @override
  String get k => 'hub';
}

class RLobby extends R {
  const RLobby();
  @override
  String get k => 'lobby';
}

class RMatch extends R {
  final String id;
  const RMatch(this.id);
  @override
  String get k => 'match';
}

class RResult extends R {
  final OnlineOutcome o;
  final JRow? before;
  const RResult(this.o, this.before);
  @override
  String get k => 'result';
}

class RTours extends R {
  const RTours();
  @override
  String get k => 'tours';
}

class RTour extends R {
  final String id;
  const RTour(this.id);
  @override
  String get k => 'tour';
}

class RRanks extends R {
  final String tab;
  const RRanks([this.tab = 'top']);
  @override
  String get k => 'ranks';
}

class RArena extends R {
  const RArena();
  @override
  String get k => 'arena';
}

class RChallenges extends R {
  const RChallenges();
  @override
  String get k => 'challenges';
}

R _entry(OnlineEntry e) => switch (e) {
      OnlineEntry.hub => const RHub(),
      OnlineEntry.tours => const RTours(),
      OnlineEntry.ranks => const RRanks(),
      OnlineEntry.leagues => const RRanks('leagues'),
      OnlineEntry.arena => const RArena(),
      OnlineEntry.challenges => const RChallenges(),
    };

class OnlineRoot extends StatefulWidget {
  final OnlineEntry entry;
  final String? quick;
  final VoidCallback onExit;
  final Toast toast;
  final bool fx;
  const OnlineRoot({super.key, required this.entry, this.quick, required this.onExit, required this.toast, this.fx = true});
  @override
  State<OnlineRoot> createState() => _OnlineRootState();
}

class _OnlineRootState extends State<OnlineRoot> {
  late final List<R> stack = [_entry(widget.entry)];
  RoomLink? link;
  String? connErr, skip;
  bool firstLoad = true, quickDone = false;
  JRow? before;

  R get top => stack.last;

  @override
  void initState() {
    super.initState();
    _scene();
    connect();
    Auth.I.addListener(_auth);
    Matchmaker.I.onMatched = (r) {
      OracleBus.I.react(OracleEvent.matchFound);
      enterRoom(r);
    };
  }

  @override
  void dispose() {
    Auth.I.removeListener(_auth);
    Matchmaker.I.onMatched = null;
    Matchmaker.I.cancel();
    final l = link;
    if (l != null) {
      l.removeListener(_linkChanged);
      rpc('leave_room', {'p_room': l.id}).catchError((_) => null);
      l.destroy();
    }
    setAudioScene(AudioScene.menu);
    super.dispose();
  }

  void _scene() => setAudioScene(top is RMatch ? AudioScene.match : AudioScene.room); // no menu music anywhere online

  void _auth() {
    if (!mounted) return;
    setState(() {});
    _quick();
  }

  // guests are signed in anonymously on first visit
  void connect() {
    setState(() => connErr = null);
    Auth.I.ensure().then((id) {
      if (!mounted) return;
      if (id == null) setState(() => connErr = 'اتصال به سرور برقرار نشد');
      _quick();
    }, onError: (e) {
      if (mounted) setState(() => connErr = errFa(e));
    });
  }

  // Oracle "find me a quick match": once connected, queue straight away
  void _quick() {
    final q = widget.quick;
    if (q == null || Auth.I.uid == null || quickDone) return;
    quickDone = true;
    OracleBus.I.react(OracleEvent.search);
    Matchmaker.I.start(q);
  }

  void push(R r) => setState(() {
        stack.add(r);
        _scene();
      });
  void pop() => setState(() {
        if (stack.length > 1) stack.removeLast();
        _scene();
      });
  void replaceTop(R r) => setState(() {
        stack[stack.length - 1] = r;
        _scene();
      });
  void _dropRoomRoutes() {
    stack.removeWhere((x) => x is RLobby || x is RMatch || x is RResult);
    if (stack.isEmpty) stack.add(const RHub());
  }

  void dropRoom() => setState(() {
        _dropRoomRoutes();
        _scene();
      });

  void enterRoom(JRow room) {
    final uid = Auth.I.uid;
    if (uid == null) return;
    if (link != null && link!.id == room['id']) {
      setState(() {
        _dropRoomRoutes();
        stack.add(const RLobby());
        _scene();
      });
      return;
    }
    link?.removeListener(_linkChanged);
    link?.destroy();
    firstLoad = true;
    skip = null;
    final l = RoomLink(rs(room, 'id'), uid, rs(Auth.I.profile, 'username', 'Pilot'));
    l.addListener(_linkChanged);
    setState(() {
      link = l;
      _dropRoomRoutes();
      stack.add(const RLobby());
      _scene();
    });
  }

  Future<void> leaveRoom() async {
    final l = link;
    if (l == null) return dropRoom();
    try {
      await rpc('leave_room', {'p_room': l.id});
    } catch (_) {}
    l.removeListener(_linkChanged);
    l.destroy();
    if (!mounted) return;
    setState(() {
      link = null;
      _dropRoomRoutes();
      _scene();
    });
  }

  // room state → navigation
  void _linkChanged() {
    final l = link;
    if (l == null || !mounted) return;
    final ls = l.value;
    if (!ls.loaded) return;
    final room = ls.room;
    if (ls.gone) {
      if (top is RLobby || top is RResult) {
        widget.toast(room != null ? 'از اتاق خارج شدی' : 'اتاق بسته شد', 'err');
        l.removeListener(_linkChanged);
        l.destroy();
        setState(() {
          link = null;
          _dropRoomRoutes();
        });
      }
      return;
    }
    if (room == null) return;
    if (firstLoad) {
      firstLoad = false;
      // a host coming back to a room stuck in "playing" (e.g. app was killed) ends that match
      final cm = room['current_match'] as String?;
      final fresh = DateTime.tryParse(rs(room, 'updated_at'))?.isAfter(DateTime.now().subtract(const Duration(seconds: 20))) ?? false;
      if (room['status'] == 'playing' && cm != null && room['host'] == l.me && !fresh && Matchmaker.I.value.status != MMStatus.matched) {
        skip = cm;
        rpc('abandon_match', {'p_match': cm}).then((_) => l.ping(), onError: (_) {});
        return;
      }
    }
    final cm = room['current_match'] as String?;
    if (top is RLobby && room['status'] == 'playing' && cm != null && cm != skip) {
      before = Auth.I.profile;
      Matchmaker.I.reset();
      push(RMatch(cm));
    }
  }

  void back() {
    if (top is RMatch) return; // the match has its own quit dialog
    if (top is RLobby) return _confirmLeave();
    if (top is RResult) return replaceTop(const RLobby());
    if (stack.length > 1) return pop();
    if (link != null) leaveRoom();
    widget.onExit();
  }

  void _confirmLeave() => showNxModal(context, accent: C.red, builder: (c) => Padding(
        padding: const EdgeInsets.all(S.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          T('خروج از اتاق؟', align: TextAlign.center, style: fs(F.title, 20)),
          const SizedBox(height: S.s),
          T('جایگاهت آزاد می‌شود و از لابی خارج می‌شوی.', align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim)),
          const SizedBox(height: S.l),
          Btn(label: 'ماندن', onPress: () => Navigator.of(c).pop()),
          const SizedBox(height: S.s),
          Btn(label: 'خروج', small: true, colors: G.red, onPress: () {
            Navigator.of(c).pop();
            leaveRoom();
          }),
        ]),
      ));

  SpaceTheme get _space {
    final t = top;
    if (t is RResult) {
      final o = t.o;
      return o.myTeam != null && o.winner == o.myTeam ? SpaceTheme.win : o.winner == -1 || o.myTeam == null ? SpaceTheme.system : SpaceTheme.lose;
    }
    return SpaceTheme.base;
  }

  Widget _page() {
    final l = link, t = top;
    return switch (t) {
      RHub() => Hub(onBack: back, onRoom: enterRoom, toast: widget.toast, onNav: (n) => push(switch (n) {
            HubNav.tours => const RTours(),
            HubNav.ranks => const RRanks(),
            HubNav.arena => const RArena(),
            HubNav.challenges => const RChallenges(),
          })),
      RLobby() when l != null => Lobby(link: l, toast: widget.toast, onLeave: _confirmLeave, onWatch: () {
          final m = l.value.room?['current_match'] as String?;
          if (m != null) {
            before = Auth.I.profile;
            skip = null;
            push(RMatch(m));
          }
        }),
      RMatch(:final id) when l != null => OnlineMatch(
          key: ValueKey(id),
          link: l,
          matchId: id,
          toast: widget.toast,
          fx: widget.fx,
          onFinish: (o) {
            skip = id;
            playLoop(Sfx.music);
            replaceTop(RResult(o, before));
          },
          onExit: (_) {
            skip = id;
            playLoop(Sfx.music);
            replaceTop(const RLobby());
            l.refresh();
          },
        ),
      RResult(:final o, :final before) => OnlineResultScreen(o: o, before: before, onLobby: () => replaceTop(const RLobby()), onLeave: leaveRoom),
      RTours() => Tournaments(onBack: back, toast: widget.toast, onOpen: (id) => push(RTour(id))),
      RTour(:final id) => TournamentDetail(id: id, onBack: back, toast: widget.toast, onRoom: enterRoom),
      RRanks(:final tab) => Ranks(onBack: back, toast: widget.toast, tab: tab),
      RArena() => Arena(onBack: back, toast: widget.toast, onRoom: enterRoom),
      RChallenges() => ChallengesScreen(onBack: back, toast: widget.toast),
      _ => const Center(child: Spinner()),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Material(
        color: C.bg,
        child: Auth.I.uid == null
            ? Stack(children: [
                Positioned.fill(child: Space(theme: SpaceTheme.base, stars: widget.fx)),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(S.xl),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (connErr != null)
                        ErrorState(msg: connErr!, onRetry: connect)
                      else ...[
                        const Spinner(size: 40),
                        const SizedBox(height: S.m),
                        T('در حال اتصال به سرور…', style: fs(F.body, TS.body, color: C.dim)),
                      ],
                      const SizedBox(height: S.l),
                      SizedBox(width: 160, child: Btn(label: 'بازگشت', small: true, colors: G.dark, onPress: widget.onExit)),
                    ]),
                  ),
                ),
              ])
            : Stack(children: [
                if (t is! RMatch) Positioned.fill(child: Space(theme: _space, dim: .1, stars: widget.fx)),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: 220.ms,
                    reverseDuration: 120.ms,
                    transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: c)),
                    child: KeyedSubtree(key: ValueKey(t.k + (t is RTour ? t.id : t is RMatch ? t.id : '')), child: _page()),
                  ),
                ),
                if (t is! RMatch)
                  ValueListenableBuilder<MMState>(
                    valueListenable: Matchmaker.I,
                    builder: (_, s, _) => s.status == MMStatus.searching || s.status == MMStatus.failed ? Positioned.fill(child: QueueOverlay(s: s)) : const SizedBox.shrink(),
                  ),
              ]),
      ),
    );
  }
}
