// Local match screen (vs bot / local 2P) — port of src/screens/Match.tsx on Flame.
import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/data.dart';
import '../game/engine.dart';
import '../game/forge_engine.dart';
import '../game/match_game.dart';
import '../sound.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/score_bug.dart';
import '../ui/theme.dart';

class MatchResult {
  final List<int> score;
  final List<Team> teams;
  final bool ai;
  final int aiLvl;
  const MatchResult(this.score, this.teams, this.ai, this.aiLvl);
}

class _Hud {
  final int s0, s1, turn;
  final String clock;
  final double tl;
  final bool sudden;
  const _Hud(this.s0, this.s1, this.turn, this.clock, this.tl, this.sudden);
  bool same(_Hud o) => o.s0 == s0 && o.s1 == s1 && o.turn == turn && o.clock == clock && (o.tl - tl).abs() <= .02 && o.sudden == sudden;
}

/// coach hook (Oracle) — optional
typedef CoachFn = void Function(String text, String mood);

class MatchScreen extends StatefulWidget {
  final MatchCfg cfg;
  final List<Team> teams;
  final List<String> names;
  final void Function(MatchResult r) onFinish;
  final VoidCallback onQuit;
  final bool fx;
  final CoachFn? coach;
  const MatchScreen({super.key, required this.cfg, required this.teams, required this.names, required this.onFinish, required this.onQuit, this.fx = true, this.coach});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> with TickerProviderStateMixin {
  late final Engine eng;
  late final MatchGame game;
  final hud = ValueNotifier(const _Hud(0, 0, 0, '', 1, false));
  bool paused = false, ended = false;
  late final AnimationController banner = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  (String, String, Color) bText = ('', '', C.gold);
  // coach state
  int shotTeam = -1, misses = 0, reminded = -1, turnN = 0, lastTip = 0;
  bool touched = false;

  bool human(int t) => !(widget.cfg.ai && t == 1);

  @override
  void initState() {
    super.initState();
    final useForge = Store.I.p.physics == 'forge2d' && forge2dReady;
    eng = useForge ? ForgeEngine(widget.cfg) : Engine(widget.cfg);
    game = MatchGame(
      eng: eng,
      teams: widget.teams,
      ballIdx: widget.cfg.ball,
      hq: widget.fx,
      shouldStep: () => !paused,
      onTick: _tick,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    sfx(Sfx.whistle);
    playLoop(Sfx.crowd);
    stopLoop(Sfx.music);
  }

  @override
  void dispose() {
    stopLoop(Sfx.crowd);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    banner.dispose();
    super.dispose();
  }

  void _showBanner(String t, String s, Color c) {
    setState(() => bText = (t, s, c));
    banner.forward(from: 0);
  }

  void _tick(double dt) {
    if (eng.events.isNotEmpty) {
      for (final ev in eng.events) {
        switch (ev) {
          case EvHit(:final ball, :final power):
            if (ball) touched = true;
            sfx(ball ? Sfx.hitb : Sfx.hitp, power);
            if (power > .35) buzz(power > .7 ? Buzz.medium : Buzz.light);
          case EvWall(:final power):
            sfx(Sfx.wall, power);
          case EvPost(:final power):
            sfx(Sfx.post, power);
            buzz(Buzz.medium);
          case EvShot(:final team):
            buzz();
            shotTeam = team;
            touched = false;
          case EvTurn():
            turnN++;
            if (shotTeam >= 0 && human(shotTeam) && !touched) {
              misses++;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (widget.coach != null && now - lastTip > 18000) {
                lastTip = now;
                widget.coach!(eng.lastPower > .9 ? 'ضربه‌ی خیلی محکم دقتش کمه؛ کمی آرام‌تر بزن.' : 'سعی کن مستقیم به توپ بزنی؛ خط نشانه رو دنبال کن.', eng.lastPower > .9 ? 'focus' : 'idea');
              }
            }
            shotTeam = -1;
          case EvGoal(:final team, :final nogoal):
            if (nogoal) {
              _showBanner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
            } else {
              touched = true;
              sfx(Sfx.goal);
              sfx(Sfx.roar);
              buzz(Buzz.heavy);
              _showBanner('گل!', widget.names[team], team == 0 ? C.cyan : C.red);
            }
          case EvClock():
            _showBanner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
          case EvEnd(:final score):
            if (!ended) {
              ended = true;
              sfx(Sfx.finalW);
              stopLoop(Sfx.crowd);
              Timer(const Duration(milliseconds: 900), () => widget.onFinish(MatchResult(score, widget.teams, widget.cfg.ai, widget.cfg.aiLvl)));
            }
        }
      }
      eng.events.clear();
    }
    final cfg = widget.cfg;
    if (cfg.turnTime > 0 && eng.phase == Phase.aim && eng.tleft < 5 && eng.tleft > 0 && human(eng.turn) && reminded != turnN && !paused) {
      reminded = turnN;
      widget.coach?.call('۵ ثانیه وقت داری! ⏱ یک ضربه بزن.', 'alert');
    }
    if (!widget.fx && eng.parts.length > 40) eng.parts.removeRange(40, eng.parts.length);
    final m = math.max(0, eng.mleft.ceil());
    final clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}') : 'تا ${cfg.limit} گل';
    final tl = cfg.turnTime > 0 && eng.phase == Phase.aim ? math.max(0.0, eng.tleft / cfg.turnTime) : 1.0;
    final h = _Hud(eng.score[0], eng.score[1], eng.turn, clock, tl, eng.sudden);
    if (!h.same(hud.value)) hud.value = h;
  }

  Offset? _w(Offset p) => game.worldAt(p);

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    game.setInsets(ins.top + 86, ins.bottom + 22);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => setState(() => paused = true),
      child: Scaffold(
        backgroundColor: hex('#02040c'),
        body: Stack(children: [
          // raw pointer events: lowest-latency path into the engine (no gesture arena delay)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                final p = _w(e.localPosition);
                if (p != null && eng.pick(p.dx, p.dy)) buzz();
              },
              onPointerMove: (e) {
                final p = _w(e.localPosition);
                if (p != null) eng.move(p.dx, p.dy);
              },
              onPointerUp: (_) => eng.release(),
              onPointerCancel: (_) => eng.cancel(),
              child: GameWidget(game: game),
            ),
          ),
          Positioned(
            top: ins.top + 6, left: 10, right: 10,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Press(
                  onPress: () => setState(() => paused = true),
                  child: Container(
                    width: 38, height: 38, alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: rgba(5, 8, 22, .9), border: Border.all(color: const Color(0x29FFFFFF))),
                    child: T('II', style: fs(F.title, 13, color: Colors.white)),
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<_Hud>(
                  valueListenable: hud,
                  builder: (_, h, _) => ScoreBug(
                    left: BugSide(team: widget.teams[0], name: widget.names[0], score: h.s0, color: C.cyan, on: h.turn == 0),
                    right: BugSide(team: widget.teams[1], name: widget.names[1], score: h.s1, color: C.red, on: h.turn == 1),
                    clock: h.clock, sudden: h.sudden, tl: h.tl, timed: widget.cfg.turnTime > 0,
                    status: h.turn == 0 ? 'نوبت توئه' : 'نوبت حریف',
                  ),
                ),
              ),
            ]),
          ),
          // goal banner: spring in, hold, scale out
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: banner,
                builder: (_, _) {
                  final t = banner.value * 1.7; // seconds
                  if (banner.isDismissed || t <= 0) return const SizedBox.shrink();
                  final inK = Curves.elasticOut.transform(math.min(1, t / .55));
                  final out = t > 1.4 ? (t - 1.4) / .3 : 0.0;
                  final sc = .3 + .7 * inK + .25 * out;
                  final op = (t < .1 ? t / .1 : 1.0) * (1 - out).clamp(0.0, 1.0);
                  return Align(
                    alignment: const Alignment(0, -.24),
                    child: Opacity(
                      opacity: op.clamp(0, 1),
                      child: Transform.scale(
                        scale: sc,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          T(bText.$1, style: fs(F.title, 54, ls: 4, color: Colors.white, shadows: [Shadow(color: bText.$3, blurRadius: 24), Shadow(color: bText.$3, blurRadius: 48)])),
                          if (bText.$2.isNotEmpty) T(bText.$2, style: fs(F.head, 13, ls: 3, color: bText.$3)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (paused)
            Positioned.fill(
              child: Container(
                color: rgba(2, 4, 14, .7),
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: .82,
                  child: Panel(
                    glow: true,
                    pad: const EdgeInsets.all(22),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(child: T('توقف', style: fs(F.title, 24, ls: 6))),
                      const SizedBox(height: 18),
                      Btn(label: 'ادامه', onPress: () => setState(() => paused = false)),
                      const SizedBox(height: 12),
                      Btn(
                        label: 'شروع دوباره',
                        colors: G.dark,
                        small: true,
                        onPress: () => setState(() {
                          eng.score[0] = 0;
                          eng.score[1] = 0;
                          eng.mleft = widget.cfg.matchTime;
                          eng.sudden = false;
                          eng.reset(0);
                          paused = false;
                        }),
                      ),
                      const SizedBox(height: 12),
                      Btn(label: 'خروج', colors: G.red, onPress: () {
                        stopLoop(Sfx.crowd);
                        widget.onQuit();
                      }),
                    ]),
                  ),
                ).animate().scale(begin: const Offset(.85, .85), curve: Curves.easeOutBack, duration: 280.ms).fadeIn(),
              ),
            ),
        ]),
      ),
    );
  }
}
