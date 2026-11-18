import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../arcade_kit/arcade_turns.dart';
import '../../core/game_contract.dart';
import '../core/spy_core.dart';

/// Sprite keys: card_back (portrait), spy, agent, loc_0 .. loc_11 (location art), table (background).
ArcadeSkin spySkin() => ArcadeSkin(
      gameId: 'spy_mafia',
      bgTop: const Color(0xFF1A1030),
      bgBottom: const Color(0xFF05030B),
      accent: const Color(0xFFB98CFF),
      accent2: const Color(0xFFFF4F6D),
      glow: const Color(0xFF7A4DFF),
      players: const <Color>[
        Color(0xFF39C6FF), Color(0xFFFF4F9A), Color(0xFFFFC94A), Color(0xFF7CFF7A),
        Color(0xFFB98CFF), Color(0xFFFF8A2A), Color(0xFF2EE6D6), Color(0xFFE9E3D4),
      ],
    );

class SpyGameView extends StatefulWidget {
  const SpyGameView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<SpyGameView> createState() => _SpyGameViewState();
}

class _SpyGameViewState extends ArcadeLoopState<SpyGameView> {
  late final SpyGame g;
  late final ArcadeSkin skin = spySkin();
  late final ArcadeFx fx;
  ArcadeTurnNet? tn;
  final math.Random _rng = math.Random(5);
  double _botT = 0;
  double _phaseT = 0;
  SpyPhase _lastPhase = SpyPhase.clues;
  bool _done = false;
  bool _peek = true;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(4, 8);
  bool _isBot(int s) => !l.online && s != me;
  double get _skill => botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);

  String _word(int ref) {
    final SpyLocation loc = kSpyLocations[spyWordLoc(ref)];
    final int w = ref % 6;
    return l.isFa ? loc.wordsFa[w] : loc.wordsEn[w];
  }

  String _locName(int i) => l.isFa ? kSpyLocations[i].fa : kSpyLocations[i].en;
  String _name(int s) => l.netName(s) ?? (s == me ? l.playerName : '${l.tx('ربات', 'Bot')} ${s + 1}');

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    g = SpyGame(players: seats, seed: l.net?.seed ?? l.seed ?? 21);
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      tn = ArcadeTurnNet(n, onMove: _onNet, onReplayDone: () => setState(() => tn?.turn = _turnSeat))..start();
      for (final int s in n.forfeitedSeats) {
        g.leave(s);
      }
    }
  }

  @override
  void dispose() {
    tn?.dispose();
    super.dispose();
  }

  int? get _turnSeat => switch (g.phase) {
        SpyPhase.clues => g.turn,
        SpyPhase.guess => g.accused,
        _ => null,
      };

  Future<void> _onNet(NetMove m) async {
    if (!m.replay && m.seat == me) return;
    if (m.isForfeit) {
      g.leave((m.data['seat'] as num?)?.toInt() ?? m.seat);
    } else if (m.isTimeout) {
      if (g.phase == SpyPhase.clues) g.giveClue(g.turn, 0);
      if (g.phase == SpyPhase.guess) g.guess(-1);
    } else {
      final String a = '${m.data['a']}';
      final int v = (m.data['v'] as num?)?.toInt() ?? 0;
      if (a == 'clue') g.giveClue(m.seat, v);
      if (a == 'vote') g.vote(m.seat, v);
      if (a == 'guess') g.guess(v);
    }
    tn?.turn = _turnSeat;
    if (mounted) setState(() {});
  }

  void _act(String a, int v) {
    bool ok = false;
    if (a == 'clue') ok = g.giveClue(me, v);
    if (a == 'vote') ok = g.vote(me, v);
    if (a == 'guess') ok = g.guess(v);
    if (!ok) return;
    HapticFeedback.selectionClick();
    if (tn != null) {
      unawaited(tn!.send(<String, dynamic>{'a': a, 'v': v}));
      tn!.turn = _turnSeat;
    }
    setState(() {});
  }

  @override
  void tick(double dt) {
    _phaseT += dt;
    if (g.phase != _lastPhase) {
      _lastPhase = g.phase;
      _phaseT = 0;
      if (g.phase == SpyPhase.vote) HapticFeedback.mediumImpact();
      if (g.phase == SpyPhase.over) _finish();
      setState(() {});
    }
    // offline bots
    if (!l.online && !g.over) {
      _botT += dt;
      if (_botT > 1.1) {
        _botT = 0;
        bool changed = false;
        if (g.phase == SpyPhase.clues && _isBot(g.turn)) {
          changed = g.giveClue(g.turn, g.botClue(g.turn, _rng));
        } else if (g.phase == SpyPhase.vote) {
          for (int s = 0; s < g.players; s++) {
            if (_isBot(s) && !g.votes.containsKey(s)) {
              changed = g.vote(s, g.botVote(s, _rng, _skill));
              break;
            }
          }
        } else if (g.phase == SpyPhase.guess && g.accused != null && _isBot(g.accused!)) {
          changed = g.guess(g.botGuess(_rng, _skill));
        }
        if (changed) setState(() {});
      }
    }
    // online: the authority files an abstain for players who never voted (30 s)
    final ArcadeTurnNet? t = tn;
    if (t != null && t.isAuthority && g.phase == SpyPhase.vote && _phaseT > 30) {
      _phaseT = 0;
      for (final int s in g.activeSeats) {
        if (!g.votes.containsKey(s) && s != me) {
          unawaited(t.send(<String, dynamic>{'a': 'vote', 'v': -1}, asSeat: s));
          g.vote(s, -1);
        }
      }
    }
    fx.update(dt);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = g.ranking();
    final bool won = order.isNotEmpty && g.isSpy(me) == g.spiesWin;
    if (won) {
      fx.confetti(MediaQuery.sizeOf(context).center(Offset.zero), count: 60);
      HapticFeedback.heavyImpact();
    }
    Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      // the winning team shares first place: put me first among winners so my own result reads correctly
      final List<int> o = List<int>.of(order);
      if (won) {
        o
          ..remove(me)
          ..insert(0, me);
      }
      l.onFinish(rankedResult(l, o,
          whatFa: g.isSpy(me) ? 'جاسوس' : 'مأمور', whatEn: g.isSpy(me) ? 'Spy' : 'Agent'));
    });
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      CustomPaint(painter: ArcadePainter((Canvas c, Size s) {
        paintBackdrop(c, s, skin, time);
        // slow spotlight sweep
        final double x = s.width * (0.5 + 0.35 * math.sin(time * 0.4));
        paintGlow(c, Offset(x, s.height * 0.3), s.width * 0.6, skin.glow, 0.16);
        fx.paint(c);
      }, frame)),
      Positioned.fill(
        top: pad.top + 60,
        bottom: pad.bottom + 8,
        child: Column(children: <Widget>[
          _roleCard(),
          const SizedBox(height: 10),
          _phaseLine(),
          const SizedBox(height: 8),
          Expanded(child: _players()),
          _actions(),
        ]),
      ),
    ]);
  }

  Widget _roleCard() {
    final bool spy = g.isSpy(me);
    final Color c = spy ? skin.accent2 : skin.accent;
    return GestureDetector(
      onTap: () => setState(() => _peek = !_peek),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: <Color>[c.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.55)]),
          border: Border.all(color: c.withValues(alpha: 0.8), width: 1.4),
          boxShadow: <BoxShadow>[BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 22)],
        ),
        child: Row(children: <Widget>[
          Icon(_peek ? (spy ? Icons.visibility_off_rounded : Icons.badge_rounded) : Icons.lock_rounded, color: c, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(
                  !_peek
                      ? l.tx('کارت نقش (برای دیدن لمس کن)', 'Role card (tap to peek)')
                      : spy
                          ? l.tx(g.spies.length > 1 ? 'تو جاسوسی (مافیا)' : 'تو جاسوسی!', g.spies.length > 1 ? 'You are a SPY (mafia)' : 'You are the SPY!')
                          : l.tx('تو مأموری', 'You are an AGENT'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 2),
              Text(
                  !_peek
                      ? '••••••'
                      : spy
                          ? l.tx('مکان را نمی‌دانی؛ بلوف بزن و حدسش بزن', "You don't know the place — bluff and work it out")
                          : '${l.tx('مکان', 'Location')}: ${_locName(g.location)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _phaseLine() {
    final String t = switch (g.phase) {
      SpyPhase.clues => g.turn == me
          ? l.tx('نوبت توست: یک سرنخ انتخاب کن', 'Your turn: pick a clue')
          : l.tx('${_name(g.turn)} سرنخ می‌دهد… (دور ${g.round + 1}/${g.rounds})', '${_name(g.turn)} is giving a clue… (round ${g.round + 1}/${g.rounds})'),
      SpyPhase.vote => g.votes.containsKey(me)
          ? l.tx('منتظر رأی بقیه…', 'Waiting for the other votes…')
          : l.tx('رأی‌گیری: به مشکوک‌ترین بازیکن رأی بده', 'VOTE: tap the most suspicious player'),
      SpyPhase.guess => g.accused == me
          ? l.tx('لو رفتی! مکان را حدس بزن تا ببری', 'Caught! Name the location to steal the win')
          : l.tx('${_name(g.accused ?? 0)} لو رفت… حدس می‌زند', '${_name(g.accused ?? 0)} was caught… guessing the place'),
      SpyPhase.over => g.spiesWin
          ? l.tx('جاسوس برد! مکان: ${_locName(g.location)}', 'The SPY wins! It was: ${_locName(g.location)}')
          : l.tx('مأمورها بردند! مکان: ${_locName(g.location)}', 'AGENTS win! It was: ${_locName(g.location)}'),
    };
    return ArcadeBanner(t, color: g.phase == SpyPhase.over ? skin.accent2 : skin.accent, size: 16);
  }

  Widget _players() {
    final Map<int, int> votes = g.tally();
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.55,
      children: <Widget>[
        for (int s = 0; s < g.players; s++) _playerTile(s, votes[s] ?? 0),
      ],
    );
  }

  Widget _playerTile(int s, int votesFor) {
    final bool turn = g.phase == SpyPhase.clues && g.turn == s;
    final bool canVote = g.phase == SpyPhase.vote && !g.votes.containsKey(me) && s != me && !g.out.contains(s);
    final bool reveal = g.over && g.isSpy(s);
    final Color c = skin.player(s);
    return GestureDetector(
      onTap: canVote ? () => _act('vote', s) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black.withValues(alpha: g.out.contains(s) ? 0.2 : 0.45),
          border: Border.all(
              color: reveal ? skin.accent2 : (turn ? c : (canVote ? Colors.white54 : Colors.white12)), width: turn || reveal ? 2 : 1),
          boxShadow: turn ? <BoxShadow>[BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 16)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            CircleAvatar(
                radius: 12,
                backgroundColor: c,
                child: Icon(reveal ? Icons.visibility_off_rounded : (_isBot(s) ? Icons.smart_toy_rounded : Icons.person_rounded),
                    size: 14, color: Colors.black)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(_name(s),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: g.out.contains(s) ? 0.4 : 1), fontWeight: FontWeight.w800, fontSize: 13))),
            if (g.phase != SpyPhase.clues && votesFor > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: skin.accent2, borderRadius: BorderRadius.circular(10)),
                child: Text('$votesFor', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
          ]),
          const Spacer(),
          Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
            for (final int w in g.clues[s])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.withValues(alpha: 0.5)),
                ),
                child: Text(_word(w), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            if (g.clues[s].isEmpty) Text('…', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
          ]),
          if (g.phase == SpyPhase.vote && g.votes.containsKey(s))
            Text(l.tx('رأی داد ✓', 'voted ✓'), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _actions() {
    if (g.phase == SpyPhase.clues && g.turn == me) {
      final List<int> o = g.options(me);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: <Widget>[
          for (int i = 0; i < o.length; i++)
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _btn(_word(o[i]), skin.accent, () => _act('clue', i)))),
        ]),
      );
    }
    if (g.phase == SpyPhase.guess && g.accused == me) {
      final List<int> o = g.guessOptions();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: <Widget>[
          for (final int loc in o) SizedBox(width: 160, child: _btn(_locName(loc), skin.accent2, () => _act('guess', loc))),
        ]),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _btn(String t, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[shade(c, 0.1), shade(c, -0.18)]),
            boxShadow: <BoxShadow>[BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
        ),
      );
}
