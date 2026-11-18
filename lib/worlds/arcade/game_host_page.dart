import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/music_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../core/online/online_service.dart';
import '../../games/arcade_kit/arcade_meta.dart';
import '../../games/game_registry.dart';
import '../oracle_core/oracle_game_sheet.dart';
import '../oracle_core/persona/oracle_persona.dart';
import '../oracle_core/persona/oracle_persona_widgets.dart';

/// Hosts any GameModule: exit button, pause-confirm, result screen, XP, rematch.
class GameHostPage extends ConsumerStatefulWidget {
  const GameHostPage({
    super.key,
    required this.game,
    required this.mode,
    required this.difficulty,
    required this.players,
    this.daily = false,
  });
  final GameInfo game;

  /// Daily challenge run (today's seed; arcade games only).
  final bool daily;
  final GameMode mode;
  final BotDifficulty difficulty;
  final int players;

  @override
  ConsumerState<GameHostPage> createState() => _GameHostPageState();
}

class _GameHostPageState extends ConsumerState<GameHostPage> {
  @override
  void initState() {
    super.initState();
    MusicService.instance.enterGame();
  }

  @override
  void dispose() {
    MusicService.instance.exitGame();
    super.dispose();
  }

  int _round = 0;
  GameResult? _result;
  AwardOutcome? _award;
  bool _finished = false;
  String? _oracleLine;
  ArcadeRecordResult? _arcade;

  void _onFinish(GameResult r) {
    if (_finished) return;
    _finished = true;
    final p = ref.read(profileProvider);
    final outcome = switch (r.outcome) {
      GameOutcome.win => 'win',
      GameOutcome.loss => 'loss',
      GameOutcome.draw => 'draw',
    };
    final award = p.recordGame(
      gameId: widget.game.id,
      gameNameFa: widget.game.nameFa,
      gameNameEn: widget.game.nameEn,
      outcome: outcome,
      score: r.score,
      vsBot: widget.mode == GameMode.vsBot,
    );
    if (kArcadeDefs.containsKey(widget.game.id)) {
      final bool multi = !widget.game.solo;
      _arcade = ArcadeRecords.record(widget.game.id, r.score,
          profile: p, daily: widget.daily, dailyWon: multi ? r.outcome == GameOutcome.win : null);
      if (widget.game.solo) {
        unawaited(ArcadeOnline.submit(ref.read(onlineProvider), widget.game.id, r.score,
            durationMs: r.durationMs ?? 0, daily: widget.daily));
      }
    }
    if (ref.read(settingsProvider).haptics) HapticFeedback.heavyImpact();
    _oracleLine = OraclePersona.instance.resultReaction(outcome: outcome, myScore: r.score, oppScore: r.opponentScore);
    // Let the game's own final animation breathe before the overlay.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _result = r;
        _award = award;
      });
    });
  }

  void _rematch() {
    setState(() {
      _round++;
      _result = null;
      _award = null;
      _finished = false;
      _oracleLine = null;
      _arcade = null;
    });
  }

  Future<bool> _confirmExit() async {
    if (_finished) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tx('خروج از بازی؟', 'Leave the match?')),
        content: Text(ctx.tx('پیشرفت این دست ذخیره نمی‌شود.',
            'Progress in this match will be lost.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('ادامه', 'Keep playing'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tx('خروج', 'Leave'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final p = ref.read(profileProvider);
    final launch = GameLaunch(
      gameId: widget.game.id,
      mode: widget.mode,
      difficulty: widget.difficulty,
      playerName: p.username.isEmpty ? 'Explorer' : p.username,
      isFa: s.isFa,
      fancyEffects: s.fancyEffects,
      reducedMotion: s.reducedMotion,
      soundOn: s.sound && s.haptics,
      playerCount: widget.players,
      skins: Map<String, String>.from(p.equipped),
      seed: widget.daily ? ArcadeDaily.seed(widget.game.id) : DateTime.now().millisecondsSinceEpoch ^ _round,
      daily: widget.daily,
      onFinish: _onFinish,
    );
    final Widget gameView = KeyedSubtree(
      key: ValueKey('round_$_round'),
      child: widget.game.builder(launch),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmExit()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: NxColors.navyDeep,
        body: Stack(children: [
          Positioned.fill(
            child: gameView,
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 6,
            start: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await _confirmExit()) nav.pop();
                },
              ),
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 6,
            end: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'ORACLE',
                icon: const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF)),
                onPressed: () => OracleGameSheet.show(context, widget.game),
              ),
            ),
          ),
          if (_result == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 58,
              left: 0,
              right: 0,
              child: OracleTutorialBanner(key: ValueKey<String>('tut_${widget.game.id}_$_round'), gameId: widget.game.id),
            ),
          if (_result != null)
            Positioned.fill(child: _resultOverlay(context, _result!, _award)),
        ]),
      ),
    );
  }

  Widget _resultOverlay(BuildContext context, GameResult r, AwardOutcome? a) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final (String title, Color color, IconData icon) = switch (r.outcome) {
      GameOutcome.win => (
          context.tx('پیروزی!', 'Victory!'),
          visual.accent,
          Icons.emoji_events_rounded
        ),
      GameOutcome.draw => (
          context.tx('مساوی', 'Draw'),
          visual.accentSecondary,
          Icons.handshake_rounded
        ),
      GameOutcome.loss => (
          context.tx('شکست', 'Defeat'),
          NxColors.danger,
          Icons.sentiment_dissatisfied_rounded
        ),
    };
    final summary = context.tx(r.summaryFa, r.summaryEn);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(NxSpace.lg),
        child: GlassPanel(
          borderColor: color.withValues(alpha: 0.7),
          padding: const EdgeInsets.all(NxSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w900, color: color)),
            if (r.score != 0 || r.opponentScore != 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${r.score}  —  ${r.opponentScore}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
              ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(summary,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NxColors.textDim)),
              ),
            if (_oracleLine != null) OracleResultLine(text: _oracleLine!),
            if (_arcade != null) _arcadeLine(context, _arcade!),
            if (a != null) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                NxPill(
                    label: '+${a.xp} XP',
                    icon: Icons.bolt_rounded,
                    color: NxColors.turquoise),
                const SizedBox(width: 8),
                NxPill(
                    label: '+${a.coins}',
                    icon: Icons.toll_rounded,
                    color: NxColors.gold),
              ]),
              if (a.levelUp)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      context.tx('سطح ${a.newLevel}!', 'Level ${a.newLevel}!'),
                      style: const TextStyle(
                          color: NxColors.turquoise,
                          fontWeight: FontWeight.w900,
                          fontSize: 18)),
                ),
              for (final ach in a.unlocked)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('🏆 ${context.tx(ach.nameFa, ach.nameEn)}',
                      style: const TextStyle(color: NxColors.gold)),
                ),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tx('آرکید', 'Arcade')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _rematch,
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(context.tx('دوباره', 'Rematch')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _arcadeLine(BuildContext context, ArcadeRecordResult a) {
    final List<Widget> chips = <Widget>[];
    if (widget.game.solo && a.medal != ArcadeMedal.none) {
      final (String fa, String en, Color c) = switch (a.medal) {
        ArcadeMedal.gold => ('مدال طلا', 'Gold medal', const Color(0xFFFFD34E)),
        ArcadeMedal.silver => ('مدال نقره', 'Silver medal', const Color(0xFFD7DEEA)),
        _ => ('مدال برنز', 'Bronze medal', const Color(0xFFE09A5B)),
      };
      chips.add(NxPill(label: context.tx(fa, en), icon: Icons.military_tech_rounded, color: c));
    }
    if (widget.game.solo && a.newBest) {
      chips.add(NxPill(label: context.tx('رکورد جدید', 'New best'), icon: Icons.trending_up_rounded, color: NxColors.gold));
    }
    if (a.dailyJustDone) {
      chips.add(NxPill(label: context.tx('چالش روزانه +۸۰ XP', 'Daily challenge +80 XP'), icon: Icons.today_rounded,
          color: NxColors.turquoise));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: chips),
    );
  }
}
