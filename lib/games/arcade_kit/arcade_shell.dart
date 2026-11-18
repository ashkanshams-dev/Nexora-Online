import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_service.dart';
import '../core/game_contract.dart';
import 'arcade_fx.dart';
import 'arcade_meta.dart';
import 'arcade_skin.dart';

/// Run controller handed to a solo arcade game by [ArcadeSoloShell].
class SoloRun {
  SoloRun({required this.launch, required this.skin, required this.seed});
  final GameLaunch launch;
  final ArcadeSkin skin;
  final int seed;
  final ValueNotifier<int> score = ValueNotifier<int>(0);

  /// Extra HUD line (combo, level, speed …) owned by the game.
  final ValueNotifier<String> status = ValueNotifier<String>('');
  bool playing = false;
  bool over = false;
  DateTime? _startedAt;

  bool get daily => launch.daily;
  void Function()? _onOver;

  void add(int n) => score.value += n;
  void set(int n) => score.value = n;

  /// Ends the run (idempotent).
  void gameOver() {
    if (over || !playing) return;
    over = true;
    playing = false;
    _onOver?.call();
  }

  int get elapsedMs => _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds;
}

/// Common frame for the 10 solo games: quick start card, score HUD (score · best · daily target),
/// game-over celebration and the hand-off to the host result screen (XP, coins, medals, rematch).
class ArcadeSoloShell extends ConsumerStatefulWidget {
  const ArcadeSoloShell({
    super.key,
    required this.launch,
    required this.skin,
    required this.titleFa,
    required this.titleEn,
    required this.hintFa,
    required this.hintEn,
    required this.builder,
  });
  final GameLaunch launch;
  final ArcadeSkin skin;
  final String titleFa;
  final String titleEn;
  final String hintFa;
  final String hintEn;

  /// Builds the game. It must start its simulation when [SoloRun.playing] becomes true (the shell calls
  /// the game's `start` through [SoloRunScope.onStart]).
  final Widget Function(BuildContext context, SoloRun run) builder;

  @override
  ConsumerState<ArcadeSoloShell> createState() => _ArcadeSoloShellState();
}

class _ArcadeSoloShellState extends ConsumerState<ArcadeSoloShell> with TickerProviderStateMixin {
  late final SoloRun run;
  late final AnimationController _pulse;
  int _best = 0;
  int _target = 0;
  bool _overShown = false;
  bool _newBest = false;

  String get _id => widget.launch.gameId;

  @override
  void initState() {
    super.initState();
    final int seed = widget.launch.daily ? ArcadeDaily.seed(_id) : (widget.launch.seed ?? DateTime.now().millisecondsSinceEpoch);
    run = SoloRun(launch: widget.launch, skin: widget.skin, seed: seed);
    run._onOver = _onOver;
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    final ProfileService p = ref.read(profileProvider);
    _best = ArcadeRecords.best(_id, p);
    _target = ArcadeDaily.target(_id);
  }

  @override
  void dispose() {
    _pulse.dispose();
    run.score.dispose();
    run.status.dispose();
    super.dispose();
  }

  void _start() {
    if (run.playing || run.over) return;
    HapticFeedback.lightImpact();
    setState(() {
      run.playing = true;
      run._startedAt = DateTime.now();
    });
  }

  void _onOver() {
    final int score = run.score.value;
    _newBest = score > _best && score > 0;
    HapticFeedback.mediumImpact();
    setState(() => _overShown = true);
    final ArcadeDef? def = kArcadeDefs[_id];
    final ArcadeMedal medal = def?.medalFor(score) ?? ArcadeMedal.none;
    final bool dailyHit = widget.launch.daily && score >= _target;
    final GameOutcome outcome = (_newBest || dailyHit || medal.index >= ArcadeMedal.silver.index)
        ? GameOutcome.win
        : (medal == ArcadeMedal.bronze ? GameOutcome.draw : GameOutcome.loss);
    final String unitFa = def?.unitFa ?? '';
    final String unitEn = def?.unitEn ?? '';
    final List<String> fa = <String>['$score $unitFa'];
    final List<String> en = <String>['$score $unitEn'];
    if (_newBest) {
      fa.add('رکورد جدید!');
      en.add('New personal best!');
    } else {
      fa.add('رکورد: $_best');
      en.add('Best: $_best');
    }
    if (widget.launch.daily) {
      fa.add(dailyHit ? 'چالش روزانه ✓' : 'هدف روزانه: $_target');
      en.add(dailyHit ? 'Daily challenge ✓' : 'Daily target: $_target');
    }
    Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      widget.launch.onFinish(GameResult(
        outcome: outcome,
        score: score,
        summaryFa: fa.join(' · '),
        summaryEn: en.join(' · '),
        durationMs: run.elapsedMs,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final GameLaunch l = widget.launch;
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final ArcadeSkin s = widget.skin;
    return Stack(fit: StackFit.expand, children: <Widget>[
      widget.builder(context, run),
      // HUD
      Positioned(
        top: pad.top + 10,
        left: 64,
        right: 64,
        child: IgnorePointer(
          child: Column(children: <Widget>[
            ValueListenableBuilder<int>(
              valueListenable: run.score,
              builder: (_, int v, __) => TweenAnimationBuilder<double>(
                key: ValueKey<int>(v),
                tween: Tween<double>(begin: 1.25, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (_, double k, Widget? child) => Transform.scale(scale: k, child: child),
                child: Text('$v',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                      shadows: <Shadow>[
                        Shadow(color: s.accent.withValues(alpha: 0.9), blurRadius: 18),
                        const Shadow(color: Colors.black54, offset: Offset(0, 3), blurRadius: 4),
                      ],
                    )),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              _chip(Icons.emoji_events_rounded, '${math.max(_best, run.score.value)}', const Color(0xFFFFC94A)),
              if (l.daily) ...<Widget>[
                const SizedBox(width: 6),
                _chip(Icons.today_rounded, '$_target', s.accent),
              ],
            ]),
            ValueListenableBuilder<String>(
              valueListenable: run.status,
              builder: (_, String v, __) => v.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(v,
                          style: TextStyle(
                              color: s.accent2,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 4)])),
                    ),
            ),
          ]),
        ),
      ),
      if (!run.playing && !run.over) Positioned.fill(child: _readyCard(context)),
      if (_overShown) Positioned.fill(child: IgnorePointer(child: _overCard(context))),
    ]);
  }

  Widget _chip(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(i, size: 13, color: c),
          const SizedBox(width: 4),
          Text(t, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      );

  Widget _readyCard(BuildContext context) {
    final GameLaunch l = widget.launch;
    final ArcadeSkin s = widget.skin;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _start,
      child: Container(
        color: Colors.black.withValues(alpha: 0.38),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(l.tx(widget.titleFa, widget.titleEn),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: <Shadow>[Shadow(color: s.accent, blurRadius: 24), const Shadow(color: Colors.black, blurRadius: 6)],
              )),
          if (l.daily)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _chip(Icons.today_rounded, l.tx('چالش روزانه · هدف $_target', 'Daily challenge · target $_target'), s.accent),
            ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, Widget? child) => Transform.scale(scale: 0.95 + _pulse.value * 0.08, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: LinearGradient(colors: <Color>[s.accent, s.accent2]),
                boxShadow: <BoxShadow>[BoxShadow(color: s.accent.withValues(alpha: 0.6), blurRadius: 24)],
              ),
              child: Text(l.tx('برای شروع لمس کن', 'TAP TO PLAY'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Text(l.tx(widget.hintFa, widget.hintEn),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13.5, height: 1.5)),
          ),
          const SizedBox(height: 10),
          if (_best > 0)
            Text(l.tx('رکورد شخصی: $_best', 'Personal best: $_best'),
                style: const TextStyle(color: Color(0xFFFFC94A), fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _overCard(BuildContext context) {
    final GameLaunch l = widget.launch;
    final ArcadeSkin s = widget.skin;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (_, double k, __) => Container(
        color: Colors.black.withValues(alpha: 0.35 * k.clamp(0, 1)),
        alignment: Alignment.center,
        child: Transform.scale(
          scale: 0.6 + 0.4 * k,
          child: Opacity(
            opacity: k.clamp(0, 1),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(_newBest ? l.tx('رکورد جدید!', 'NEW BEST!') : l.tx('پایان', 'GAME OVER'),
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: _newBest ? const Color(0xFFFFD34E) : Colors.white,
                    shadows: <Shadow>[Shadow(color: _newBest ? const Color(0xFFFF9D2E) : s.accent, blurRadius: 26)],
                  )),
              Text('${run.score.value}',
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'ChakraPetch')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Convenience: a game canvas that fills the shell and forwards pointer input.
class ArcadeCanvas extends StatelessWidget {
  const ArcadeCanvas({super.key, required this.painter, this.onPanStart, this.onPanUpdate, this.onPanEnd, this.onTapDown});
  final CustomPainter painter;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureTapDownCallback? onTapDown;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onTapDown: onTapDown,
        child: CustomPaint(painter: painter, size: Size.infinite),
      );
}

/// Draw helper re-export so games only import the kit.
typedef Fx = ArcadeFx;
