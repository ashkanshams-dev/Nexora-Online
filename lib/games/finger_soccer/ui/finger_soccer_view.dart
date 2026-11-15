import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/games/core/game_contract.dart';
import '../core/config.dart';
import '../core/fs_match.dart';
import 'fs_controller.dart';
import 'fs_fx.dart';
import 'fs_painter.dart';

/// Full-screen Finger Soccer match (host provides Scaffold + exit button + result screen).
class FingerSoccerView extends StatefulWidget {
  const FingerSoccerView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<FingerSoccerView> createState() => _FingerSoccerViewState();
}

class _FingerSoccerViewState extends State<FingerSoccerView> with SingleTickerProviderStateMixin {
  late final FsController _c;
  late final Ticker _ticker;
  final FsImages _images = FsImages();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _c = FsController(widget.launch);
    _ticker = createTicker(_onTick);
    _ticker.start();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final pitch = await fsLoadImage(AppAssets.gamesFingerSoccerPitch, 900);
    final ball = await fsLoadImage(AppAssets.gamesFingerSoccerBall, 96);
    final p0 = await fsLoadImage(AppAssets.puckTop(_c.playerSkin), 160);
    final p1 = await fsLoadImage(AppAssets.puckTop(_c.opponentSkin), 160);
    if (!mounted) {
      pitch?.dispose();
      ball?.dispose();
      p0?.dispose();
      p1?.dispose();
      return;
    }
    setState(() {
      _images.pitch = pitch;
      _images.ball = ball;
      _images.puck0 = p0;
      _images.puck1 = p1;
    });
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _c.tick(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _c.dispose();
    _images.pitch?.dispose();
    _images.ball?.dispose();
    _images.puck0?.dispose();
    _images.puck1?.dispose();
    _images.pitch = null;
    _images.ball = null;
    _images.puck0 = null;
    _images.puck1 = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final launch = widget.launch;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF050818), Color(0xFF0B1442), Color(0xFF07152A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<FsHudData>(
                valueListenable: _c.hud,
                builder: (BuildContext context, FsHudData h, Widget? _) => _FsHud(hud: h, c: _c, launch: launch),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints cons) {
                    _c.viewSize = Size(cons.maxWidth, cons.maxHeight);
                    final Widget pitch = GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (DragStartDetails d) => _c.onAimStart(d.localPosition),
                      onPanUpdate: (DragUpdateDetails d) => _c.onAimUpdate(d.localPosition),
                      onPanEnd: (DragEndDetails d) => _c.onAimEnd(),
                      onPanCancel: _c.onAimCancel,
                      child: CustomPaint(
                        size: Size(cons.maxWidth, cons.maxHeight),
                        painter: FsPainter(_c, _images),
                      ),
                    );
                    // Online seat 1: rotate the whole pitch so your own goal is at the bottom
                    // (touches are rotated with it, so aiming maps straight to field coordinates).
                    return _c.flipped ? Transform.rotate(angle: math.pi, child: pitch) : pitch;
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  launch.tx('مهره‌ی خودت را بکش و رها کن · اولین تیم با ۵ گل برنده است', 'Drag one of your pucks back and release · first to 5 goals wins'),
                  textAlign: TextAlign.center,
                  textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(color: Color(0x99EAF6FF), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FsHud extends StatelessWidget {
  const _FsHud({required this.hud, required this.c, required this.launch});
  final FsHudData hud;
  final FsController c;
  final GameLaunch launch;

  @override
  Widget build(BuildContext context) {
    final finished = hud.phase == FsPhase.finished;
    final turnColor = hud.turnTeam == 0 ? kFsTeam0 : kFsTeam1;
    String status;
    if (finished) {
      status = launch.tx('پایان بازی', 'Full time');
    } else if (hud.botThinking) {
      status = launch.tx('ربات فکر می‌کند…', 'Bot is thinking…');
    } else if (launch.vsBot || launch.online) {
      status = hud.turnTeam == launch.mySeat ? launch.tx('نوبت شما', 'Your turn') : launch.tx('نوبت حریف', 'Opponent');
    } else {
      status = launch.tx('نوبت ', 'Turn: ') + c.teamName(hud.turnTeam);
    }
    final double timerValue = (hud.timeLeft / FsConfig.turnSeconds).clamp(0.0, 1.0).toDouble();
    // Keep both top corners free (host exit button lives at top-start).
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 6, 64, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x2AFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: turnColor.withOpacity(finished ? 0.3 : 0.75), width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(color: turnColor.withOpacity(launch.fancyEffects ? 0.35 : 0.0), blurRadius: 18),
          ],
        ),
        child: Row(
          children: <Widget>[
            _ScoreBlock(name: c.teamName(0), score: hud.score0, color: kFsTeam0, active: !finished && hud.turnTeam == 0),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: finished ? 0 : timerValue,
                          strokeWidth: 3.5,
                          backgroundColor: const Color(0x22FFFFFF),
                          valueColor: AlwaysStoppedAnimation<Color>(hud.timeLeft <= 5 ? const Color(0xFFFF5A6E) : turnColor),
                        ),
                        Text('${hud.timeLeft}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
                    style: TextStyle(color: turnColor, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                    '${launch.tx('نوبت', 'Turn')} ${hud.turnNumber}/${FsConfig.maxTurns}',
                    textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(color: Color(0x99EAF6FF), fontSize: 10),
                  ),
                ],
              ),
            ),
            _ScoreBlock(name: c.teamName(1), score: hud.score1, color: kFsTeam1, active: !finished && hud.turnTeam == 1),
          ],
        ),
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.name, required this.score, required this.color, required this.active});
  final String name;
  final int score;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: TextStyle(
              color: color,
              fontSize: active ? 32 : 26,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[Shadow(color: color.withOpacity(0.7), blurRadius: active ? 14 : 4)],
            ),
            child: Text('$score'),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: active ? Colors.white : const Color(0x99EAF6FF), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
