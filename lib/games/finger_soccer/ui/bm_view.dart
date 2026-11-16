// BERMUDA NXG disc football inside the NEXORA hub: pre-match setup (team / formation / field / ball),
// the match (engine + painter + HUD) and the online wiring over the hub's NetLink (Supabase move log).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_audio.dart';
import 'bm_ball.dart';
import 'bm_painter.dart';

const String _a = 'assets/games/bermuda/';

/// Online match settings (config.js MATCH_SECONDS / TURN_SECONDS).
const int kBmMatchSeconds = 300;
const double kBmOnlineTurnSeconds = 15;

class BermudaView extends StatefulWidget {
  const BermudaView({super.key, required this.launch, this.autoStart = false});
  final GameLaunch launch;

  /// Offline only: skip the setup screen with the saved/default picks (used by tests).
  final bool autoStart;

  @override
  State<BermudaView> createState() => _BermudaViewState();
}

class _Setup {
  _Setup(this.team, this.form, this.field, this.ball);
  String team;
  int form, field, ball;
  Map<String, dynamic> toJson() => <String, dynamic>{'a': 'setup', 'team': team, 'form': form, 'field': field, 'ball': ball};
  static _Setup? fromJson(Map<String, dynamic> d) {
    final String? t = d['team'] as String?;
    if (t == null) return null;
    int i(String k) => (d[k] as num?)?.toInt() ?? 0;
    return _Setup(t, i('form').clamp(0, kBmForms.length - 1).toInt(), i('field').clamp(0, kBmFields.length - 1).toInt(), i('ball').clamp(0, NB - 1).toInt());
  }
}

class _BermudaViewState extends State<BermudaView> with TickerProviderStateMixin, WidgetsBindingObserver implements BmHooks {
  late final BmEngine e = BmEngine(this);
  final BmImages im = BmImages();
  final BmView view = BmView();
  late final BmAudio audio = BmAudio(enabled: widget.launch.soundOn);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _nowMs = 0;
  late final AnimationController _goalAnim = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  // setup
  String stage = 'setup'; // setup | waiting | match
  late _Setup my = _Setup('club0', 0, 6, 0);
  int _cat = 0;
  BmConfig? cfg;

  // toast
  String _toast = '';
  bool _toastBig = false;
  double _toastT = 0;

  // end
  double _finishIn = -1;
  bool _reported = false;
  bool _disposed = false;
  bool _paused = false;

  // online
  NetInbox? _inbox;
  bool _netReady = true;
  final Map<int, _Setup> _setups = <int, _Setup>{};
  Map<String, dynamic>? _pendingShot;
  int _pendingShotSeat = -1;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  GameLaunch get launch => widget.launch;
  bool get online => launch.online;
  int get mySeat => launch.mySeat;
  bool get isHostSeat => mySeat == 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    unawaited(audio.init());
    unawaited(_loadPrefs());
    final NetLink? net = launch.net;
    if (net != null) {
      _netReady = false;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add, onReplayDone: () => inbox.add(const NetMove(seq: -1, seat: -1, kind: 'replayDone', data: <String, dynamic>{})));
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && stage == 'setup') _startOffline();
      });
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String t = p.getString('bm.team') ?? 'club0';
      my = _Setup(kBmTeams.any((BmTeam x) => x.id == t) ? t : 'club0', (p.getInt('bm.form') ?? 0).clamp(0, kBmForms.length - 1).toInt(),
          (p.getInt('bm.field') ?? 6).clamp(0, kBmFields.length - 1).toInt(), (p.getInt('bm.ball') ?? 0).clamp(0, NB - 1).toInt());
      _cat = math.max(0, kBmCats.indexWhere((List<Object> c) => c[0] == bmTeam(my.team).cat));
      audio.announcer = p.getBool('bm.ann') ?? false; // goal announcer voice: off unless the player turns it on
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString('bm.team', my.team);
      await p.setInt('bm.form', my.form);
      await p.setInt('bm.field', my.field);
      await p.setInt('bm.ball', my.ball);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ loop
  void _onTick(Duration el) {
    double dt = (el - _last).inMicroseconds / 1e6;
    _last = el;
    if (dt < 0) dt = 0;
    _nowMs = el.inMicroseconds / 1000;
    audio.frame(dt);
    if (_toastT > 0) _toastT -= dt;
    if (stage == 'match') {
      _ensureBallRenderer();
      e.frame(dt);
      if (_waiters.isNotEmpty && e.phase != 'goal') {
        final List<Completer<void>> w = List<Completer<void>>.from(_waiters);
        _waiters.clear();
        for (final Completer<void> c in w) {
          if (!c.isCompleted) c.complete();
        }
      }
      if (_finishIn > 0) {
        _finishIn -= dt;
        if (_finishIn <= 0) _report();
      }
    }
    if (_disposed) return;
    _frame.value++;
  }

  void _ensureBallRenderer() {
    final ui.Image? b = im.ball;
    if (b == null || view.s <= 0) return;
    final double dpr = math.min(MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, 1.75);
    final int n = math.max(40, math.min(96, math.max(2, (BR * 2 * view.s * dpr).round())));
    if (im.ballR == null || im.ballR!.n != n) {
      im.ballR?.dispose();
      final BmBallRenderer r = BmBallRenderer(n);
      im.ballR = r;
      unawaited(r.setTexture(b));
    }
  }

  // ------------------------------------------------------------------ hooks
  @override
  void sfx(String k, [double v = 1]) => audio.sfx(k, v);

  @override
  void tone(String k) => audio.tone(k);

  @override
  void vib(List<int> pattern) {
    if (!launch.soundOn) return;
    final int total = pattern.fold(0, (int a, int b) => a + b);
    if (total >= 100) {
      HapticFeedback.heavyImpact();
    } else if (total >= 30) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void toast(String text, bool big) {
    _toast = text;
    _toastBig = big;
    _toastT = big ? 1.5 : 1.2;
  }

  @override
  void goalFx() {
    if (_disposed) return;
    _goalAnim.forward(from: 0);
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    final NetLink? net = launch.net;
    switch (event) {
      case 'shot':
        net?.send(<String, dynamic>{'a': 'shot', 'cid': data['cid'], 'vx': data['vx'], 'vy': data['vy']});
        break;
      case 'settled':
        net?.send(<String, dynamic>{'a': 'settled', 'snap': data['snap'], 'mt': data['mt']});
        break;
      case 'goal':
        net?.send(<String, dynamic>{'a': 'goal', 'team': data['team'], 'nogoal': data['nogoal']});
        break;
      case 'timeout':
        net?.send(<String, dynamic>{'a': 'timeout', 'seat': data['team']});
        break;
      case 'turn':
        if (net != null) net.turnSeat = data['turn'] as int;
        break;
      case 'end':
        final List<int> local = (data['local'] as List<dynamic>).cast<int>();
        _end(local);
        break;
    }
  }

  // ------------------------------------------------------------------ start / end
  void _startOffline() {
    final math.Random r = math.Random(launch.seed);
    final List<BmTeam> clubs = kBmTeams.where((BmTeam t) => t.cat == 'club' && t.id != my.team).toList();
    final String opp = clubs[r.nextInt(clubs.length)].id;
    final bool bot = launch.vsBot;
    final int lvl = switch (launch.difficulty) { BotDifficulty.easy => 0, BotDifficulty.normal => 1, BotDifficulty.hard => 2 };
    final String me = launch.playerName.isEmpty ? 'Player 1' : launch.playerName;
    _begin(BmConfig(
      mode: bot ? 'bot' : 'local',
      teams: <String>[my.team, opp],
      form: <int>[my.form, r.nextInt(6)],
      names: bot ? <String>[me, 'Bot ${<String>['Rookie', 'Pro', 'Legend'][lvl]}'] : <String>['Player 1', 'Player 2'],
      field: my.field,
      ball: my.ball,
      limit: 0,
      matchTime: kBmMatchSeconds,
      turnTime: 0,
      ai: bot,
      aiLvl: lvl,
    ));
  }

  void _maybeStartOnline({bool quiet = false}) {
    if (stage == 'match') return;
    final _Setup? h = _setups[0], g = _setups[1];
    if (h == null || g == null) return;
    final NetLink net = launch.net!;
    _begin(
        BmConfig(
          mode: 'online',
          teams: <String>[h.team, g.team],
          form: <int>[h.form, g.form],
          names: <String>[for (int s = 0; s < 2; s++) s < net.names.length ? net.names[s] : ''],
          field: h.field,
          ball: h.ball,
          limit: 0,
          matchTime: kBmMatchSeconds,
          turnTime: kBmOnlineTurnSeconds,
          mirror: mySeat == 1,
          first: 0,
        ),
        quiet: quiet);
  }

  void _begin(BmConfig c, {bool quiet = false}) {
    cfg = c;
    e.startMatch(c);
    if (quiet) e.menuOpen = false;
    stage = 'match';
    _finishIn = -1;
    _loadMatchImages(c);
    unawaited(audio.music(false));
    unawaited(audio.crowd(true));
    if (mounted) setState(() {});
  }

  Future<ui.Image?> _img(String path, {int? w}) async {
    try {
      final ByteData data = await DefaultAssetBundle.of(context).load(path);
      final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: w);
      final ui.FrameInfo f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (err) {
      debugPrint('bermuda image $path: $err');
      return null;
    }
  }

  Future<void> _loadMatchImages(BmConfig c) async {
    final BmFieldS f = kBmFields[c.field];
    final List<ui.Image?> r = await Future.wait(<Future<ui.Image?>>[
      _img('${_a}fields/${f.id}.webp'),
      _img('${_a}goals/${f.gs}.webp'),
      _img('${_a}balls/b${c.ball}.webp'),
      _img(bmTeam(c.teams[e.ct(0)]).asset, w: 192),
      _img(bmTeam(c.teams[e.ct(1)]).asset, w: 192),
    ]);
    if (!mounted || _disposed) {
      for (final ui.Image? i in r) {
        i?.dispose();
      }
      return;
    }
    im.dispose();
    im.field = r[0];
    im.goal = r[1];
    im.ball = r[2];
    im.team[0] = r[3];
    im.team[1] = r[4];
  }

  void _end(List<int> local) {
    if (_finishIn > 0 || _reported) return;
    _finishIn = 1.6;
    unawaited(audio.crowd(false));
  }

  void _report({bool forfeit = false}) {
    if (_reported) return;
    _reported = true;
    final List<int> sc = e.score; // local: [me, opponent]
    final bool won = !forfeit && sc[0] > sc[1];
    final bool draw = !forfeit && sc[0] == sc[1];
    final int winnerSeat = won ? mySeat : 1 - mySeat;
    final List<int> global = <int>[sc[e.ct(0)], sc[e.ct(1)]];
    launch.onFinish(GameResult(
      outcome: draw ? GameOutcome.draw : (won ? GameOutcome.win : GameOutcome.loss),
      score: sc[0],
      opponentScore: sc[1],
      winnerSeats: draw ? <int>[] : <int>[winnerSeat],
      scores: global,
      tournamentMatchId: launch.tournamentMatchId,
      summaryFa: 'نتیجه‌ی فوتبال: ${sc[0]} - ${sc[1]}${forfeit ? ' (انصراف)' : ''}',
      summaryEn: 'Football final: ${sc[0]} - ${sc[1]}${forfeit ? ' (forfeit)' : ''}',
    ));
  }

  // ------------------------------------------------------------------ online
  Future<void> _waitPlayable() async {
    if (stage == 'match' && e.phase != 'goal') return;
    final Completer<void> c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  Future<void> _onNet(NetMove m) async {
    if (_disposed) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      final Map<String, dynamic>? ps = _pendingShot;
      _pendingShot = null;
      if (stage == 'match') {
        e.menuOpen = false;
        if (ps != null && e.phase == 'aim') {
          if (_pendingShotSeat == mySeat) {
            // our own shot was logged but never settled: run it locally so we post the snapshot
            final int cid = (ps['cid'] as num).toInt();
            for (final BmBody b in e.bodies) {
              if (b.cid == cid) {
                final int sg = e.mirror ? -1 : 1;
                e.launch(b, (ps['vx'] as num).toDouble() * sg, (ps['vy'] as num).toDouble() * sg, false);
              }
            }
          } else {
            e.remoteShot(ps);
          }
        }
      } else if (_setups.containsKey(mySeat)) {
        stage = 'waiting';
      }
      if (mounted) setState(() {});
      return;
    }
    if (m.kind != 'move' && m.kind != 'timeout') return;
    final Map<String, dynamic> d = m.data;
    final String a = '${d['a']}';
    if (a == 'setup') {
      final _Setup? s = _Setup.fromJson(d);
      if (s != null && !_setups.containsKey(m.seat)) _setups[m.seat] = s;
      _maybeStartOnline(quiet: m.replay);
      if (mounted) setState(() {});
      return;
    }
    if (stage != 'match') return;
    if (m.replay) {
      _replayMove(m.seat, a, d);
      return;
    }
    await _waitPlayable();
    if (_disposed) return;
    switch (a) {
      case 'shot':
        e.remoteShot(d);
        break;
      case 'settled':
        e.remoteSettled(d);
        break;
      case 'goal':
        e.remoteGoal(d);
        break;
      case 'timeout':
        e.remoteTimeout(d);
        break;
    }
  }

  /// Fast-forwards the logged match after a (re)join without animating shots.
  void _replayMove(int seat, String a, Map<String, dynamic> d) {
    switch (a) {
      case 'shot':
        _pendingShot = d;
        _pendingShotSeat = seat;
        break;
      case 'settled':
        _pendingShot = null;
        final Map<String, dynamic>? snap = (d['snap'] as Map?)?.cast<String, dynamic>();
        e.applySnapshot(snap);
        final List<dynamic>? sc = snap?['sc'] as List<dynamic>?;
        if (sc != null && sc.length == 2) {
          e.score[e.ct(0)] = (sc[0] as num).toInt();
          e.score[e.ct(1)] = (sc[1] as num).toInt();
        }
        final num? tn = snap?['tn'] as num?;
        if (tn != null) e.turn = e.ct(tn.toInt());
        e.phase = 'aim';
        e.remote = false;
        e.shots = 1;
        final num? mt = d['mt'] as num?;
        if (mt != null) e.mleft = mt.toDouble();
        break;
      case 'goal':
        _pendingShot = null;
        final int t = e.ct((d['team'] as num).toInt());
        final bool ng = d['nogoal'] == true;
        if (!ng) e.score[t]++;
        e.reset(ng ? e.turn : 1 - t);
        break;
      case 'timeout':
        final num? s = d['seat'] as num?;
        if (s == null || e.ct(e.turn) == s.toInt()) {
          e.turn = 1 - e.turn;
          e.phase = 'aim';
        }
        break;
    }
  }

  void _sendSetup() {
    final NetLink? net = launch.net;
    if (net == null) return;
    _setups[mySeat] = _Setup(my.team, my.form, my.field, my.ball);
    net.send(_setups[mySeat]!.toJson());
    stage = 'waiting';
    _maybeStartOnline();
    setState(() {});
  }

  // ------------------------------------------------------------------ pause (flow.js pause())
  Future<void> _pause() async {
    if (_reported || _finishIn > 0) return;
    final bool isOnline = online, bot = launch.vsBot;
    if (!isOnline) e.menuOpen = true;
    _paused = true;
    unawaited(audio.crowd(false)); // game.js crowdSync: no crowd while the menu is open
    final String? act = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _BmDialog(
        title: launch.tx('توقف', 'Paused'),
        actions: <(String, String, IconData)>[
          ('continue', launch.tx('ادامه', 'Continue'), Icons.play_arrow_rounded),
          if (!isOnline && !bot) ('restart', launch.tx('شروع دوباره', 'Restart'), Icons.refresh_rounded),
          ('sound', launch.tx('صدا روشن/خاموش', 'Sound on/off'), Icons.volume_up_rounded),
          ('ann',
              audio.announcer ? launch.tx('گزارشگر گل: روشن', 'Goal announcer: on') : launch.tx('گزارشگر گل: خاموش', 'Goal announcer: off'),
              Icons.record_voice_over_rounded),
          ('leave', launch.tx('خروج', 'Leave'), Icons.logout_rounded),
        ],
      ),
    );
    _paused = false;
    if (!mounted) return;
    if (!isOnline) e.menuOpen = false;
    switch (act) {
      case 'restart':
        e.restart(0);
        break;
      case 'sound':
        audio.setMuted(!audio.muted);
        break;
      case 'ann':
        audio.announcer = !audio.announcer;
        unawaited(SharedPreferences.getInstance().then((SharedPreferences p) => p.setBool('bm.ann', audio.announcer)).then((_) {}, onError: (Object _) {}));
        break;
      case 'leave':
        if (isOnline || bot) {
          // flow.js: leaving counts as a loss
          _report(forfeit: true);
        } else {
          unawaited(Navigator.of(context).maybePop());
        }
        break;
    }
    _crowdSync();
  }

  /// game.js crowdSync(): crowd ambience only while a match runs, the menu is closed and the app is visible.
  void _crowdSync() {
    if (_disposed || !mounted) return;
    final bool want = stage == 'match' && !_paused && !_reported && _finishIn <= 0 && _visible;
    unawaited(audio.crowd(want));
  }

  bool _visible = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // game.js musicSync/crowdSync stop on document.hidden
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) unawaited(audio.music(false));
    _crowdSync();
    if (_visible && stage != 'match' && launch.soundOn && !_paused) unawaited(audio.music(true));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _goalAnim.dispose();
    _inbox?.close();
    for (final Completer<void> c in _waiters) {
      if (!c.isCompleted) c.complete();
    }
    audio.dispose();
    im.dispose();
    _frame.dispose();
    e.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (stage != 'match') {
      if (launch.soundOn && !_paused && _visible) unawaited(audio.music(true));
      return _setupScreen(context);
    }
    final double dpr = math.min(MediaQuery.devicePixelRatioOf(context), 1.75);
    final bool fancy = launch.fancyEffects && !launch.reducedMotion;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF03060D),
        child: Stack(children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerDown(w.dx, w.dy);
              },
              onPointerMove: (PointerMoveEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerMove(w.dx, w.dy);
              },
              onPointerUp: (_) => e.pointerUp(),
              onPointerCancel: (_) => e.pointerCancel(),
              child: CustomPaint(
                painter: BmPainter(e, im, view, () => _nowMs, dpr, fancy, repaint: _frame),
                size: Size.infinite,
              ),
            ),
          ),
          // vignette (#vig)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: .95,
                    colors: <Color>[Color(0x00000000), Color(0x00000000), Color(0x94050316)],
                    stops: <double>[0, .52, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: 0, child: SafeArea(child: _scoreboard())),
          Positioned.fill(child: IgnorePointer(child: _overlays())),
          Positioned(
            left: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: _RoundBtn(icon: Icons.pause_rounded, onTap: _pause),
          ),
        ]),
      ),
    );
  }

  Widget _overlays() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final Size sz = MediaQuery.sizeOf(context);
        return Stack(children: <Widget>[
          if (_toastT > 0)
            Positioned(
              left: 0,
              right: 0,
              top: sz.height * .30,
              child: Center(child: _ToastPill(text: _toast, big: _toastBig)),
            ),
          AnimatedBuilder(
            animation: _goalAnim,
            builder: (BuildContext context, Widget? child) {
              final double t = _goalAnim.value;
              if (t <= 0 || t >= 1 || !_goalAnim.isAnimating) return const SizedBox.shrink();
              // @keyframes goalpop
              double sc, op = 1, rot = 0, ty = 0;
              if (t < .14) {
                final double k = t / .14;
                sc = .25 + (1.2 - .25) * k;
                op = k;
                rot = -5 + 6 * k;
              } else if (t < .24) {
                final double k = (t - .14) / .10;
                sc = 1.2 + (.97 - 1.2) * k;
                rot = 1 - k;
              } else if (t < .32) {
                final double k = (t - .24) / .08;
                sc = .97 + (1.03 - .97) * k;
              } else if (t < .78) {
                sc = 1.03;
              } else {
                final double k = (t - .78) / .22;
                sc = 1.03 + (1.12 - 1.03) * k;
                op = 1 - k;
                ty = -16 * k;
              }
              return Positioned(
                left: 0,
                right: 0,
                top: sz.height * .22 + ty,
                child: Center(
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rot * math.pi / 180,
                      child: Transform.scale(scale: sc, child: child),
                    ),
                  ),
                ),
              );
            },
            child: Image.asset('${_a}ui/goal.webp', width: math.min(sz.width * .82, 460)),
          ),
        ]);
      },
    );
  }

  Widget _scoreboard() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final double sw = math.min(MediaQuery.sizeOf(context).width - 112, 440);
        final double sh = sw * .204;
        final bool aim = e.phase == 'aim';
        String clock = '';
        bool low = false;
        if (e.mt > 0) {
          if (e.sd) {
            clock = 'GOLDEN';
          } else {
            final int t = math.max(0, e.mleft.ceil());
            clock = '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
            low = t <= 30;
          }
        }
        final int tl = math.max(0, e.tleft.ceil());
        Widget team(int t) {
          final bool on = aim && e.turn == t;
          final Widget logo = Container(
            width: sh * .33 * .96,
            height: sh * .33 * .96,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x80060A1E),
              boxShadow: on ? const <BoxShadow>[BoxShadow(color: Color(0xFF3BD0FF), blurRadius: 12)] : null,
            ),
            child: ClipOval(child: Image.asset(bmTeam(e.sel[e.ct(t)]).asset, cacheWidth: 96, fit: BoxFit.contain)),
          );
          final Widget name = Expanded(
            child: Text(e.nm(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: t == 0 ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                    fontSize: sw * .026,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: on ? Colors.white : const Color(0xFFCFEAFF),
                    shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1))])),
          );
          final Widget sc = Padding(
            padding: EdgeInsets.symmetric(horizontal: sw * .006),
            child: Text('${e.score[t]}',
                style: TextStyle(
                    fontSize: sw * .058,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: t == 0 ? const Color(0xFF9FD2FF) : const Color(0xFFFF9AA8),
                    shadows: const <Shadow>[Shadow(color: Color(0xFF3BD0FF), blurRadius: 12)])),
          );
          final List<Widget> kids = <Widget>[logo, SizedBox(width: sw * .012), name, sc];
          return Opacity(
            opacity: on ? 1 : .7,
            child: Row(children: t == 0 ? kids : kids.reversed.toList()),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Center(
            child: SizedBox(
              width: sw,
              height: sh + 30,
              child: Stack(clipBehavior: Clip.none, children: <Widget>[
                Positioned(left: 0, top: 0, width: sw, height: sh, child: Image.asset('${_a}ui/sb_nx.webp', fit: BoxFit.fill)),
                Positioned(left: sw * .102, top: sh * .475, width: sw * .275, height: sh * .33, child: team(0)),
                Positioned(left: sw * .633, top: sh * .475, width: sw * .275, height: sh * .33, child: team(1)),
                Positioned(
                  left: sw * .494,
                  top: sh * .49,
                  width: sw * .096,
                  height: sh * .30,
                  child: FittedBox(
                    child: Text(clock,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: sw * (e.sd ? .026 : .044),
                          color: e.sd ? const Color(0xFFFFD84A) : (low ? const Color(0xFFFF8A98) : const Color(0xFFE8FBFF)),
                          fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
                        )),
                  ),
                ),
                if (aim && e.tt > 0)
                  Positioned(
                    left: sw / 2 - 22,
                    top: sh * 1.04,
                    width: 44,
                    height: 26,
                    child: Container(
                      alignment: Alignment.center,
                      color: e.tleft < 5 ? const Color(0xD9780A1E) : const Color(0xD90A1230),
                      child: Text('$tl', style: const TextStyle(color: Color(0xFFD8F6FF), fontWeight: FontWeight.w900, fontSize: 14)),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ setup screen
  Widget _setupScreen(BuildContext context) {
    final bool waiting = stage == 'waiting' || (online && !_netReady);
    final bool chooseArena = !online || isHostSeat;
    final List<BmTeam> teams = kBmTeams.where((BmTeam t) => t.cat == kBmCats[_cat][0]).toList();
    TextStyle h(double s) => TextStyle(color: const Color(0xFFFFD86B), fontSize: s, fontWeight: FontWeight.w900, letterSpacing: 1.2);
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
          child: AbsorbPointer(
            absorbing: waiting,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 58, 14, 20),
              children: <Widget>[
                Text(launch.tx('فوتبال انگشتی', 'FINGER SOCCER'), textAlign: TextAlign.center, style: h(22)),
                const SizedBox(height: 4),
                Text(
                    online
                        ? launch.tx('تیم و ترکیبت را انتخاب کن', 'Pick your team and formation')
                        : launch.tx('۵ دقیقه · گل طلایی در تساوی', '5 minutes · golden goal if tied'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0x99EAF6FF), fontSize: 12)),
                const SizedBox(height: 14),
                Text(launch.tx('تیم', 'TEAM'), style: h(13)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (int i = 0; i < kBmCats.length; i++)
                        _Chip(
                            label: kBmCats[i][1] as String,
                            on: _cat == i,
                            onTap: () => setState(() {
                                  _cat = i;
                                  audio.sfx('ui');
                                })),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: teams.length,
                    itemBuilder: (BuildContext c, int i) {
                      final BmTeam t = teams[i];
                      final bool on = t.id == my.team;
                      return GestureDetector(
                        onTap: () => setState(() {
                          my.team = t.id;
                          audio.sfx('ui');
                          unawaited(_savePrefs());
                        }),
                        child: Container(
                          width: 76,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: on ? const Color(0x333BD0FF) : const Color(0x14FFFFFF),
                            border: Border.all(color: on ? const Color(0xFFFFD86B) : const Color(0x22FFFFFF), width: on ? 2 : 1),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: Column(children: <Widget>[
                            Expanded(child: Image.asset(t.asset, cacheWidth: 128)),
                            Text(t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Text(launch.tx('ترکیب', 'FORMATION'), style: h(13)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  for (int i = 0; i < kBmForms.length; i++)
                    _Chip(
                        label: '${kBmForms[i][0]} · ${kBmForms[i][1]}',
                        on: my.form == i,
                        onTap: () => setState(() {
                              my.form = i;
                              audio.sfx('ui');
                              unawaited(_savePrefs());
                            })),
                ]),
                const SizedBox(height: 14),
                if (chooseArena) ...<Widget>[
                  Text(launch.tx('زمین', 'FIELD'), style: h(13)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 128,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: kBmFields.length,
                      itemBuilder: (BuildContext c, int i) {
                        final bool on = my.field == i;
                        return GestureDetector(
                          onTap: () => setState(() {
                            my.field = i;
                            audio.sfx('ui');
                            unawaited(_savePrefs());
                          }),
                          child: Container(
                            width: 78,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: on ? const Color(0xFFFFD86B) : const Color(0x22FFFFFF), width: on ? 2 : 1),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(fit: StackFit.expand, children: <Widget>[
                              Image.asset('${_a}thumbs/${kBmFields[i].id}.webp', fit: BoxFit.cover, cacheWidth: 160),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  color: const Color(0xAA000000),
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Text(kBmFields[i].name,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(launch.tx('توپ', 'BALL'), style: h(13)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 92,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: NB,
                      itemBuilder: (BuildContext c, int i) {
                        final bool on = my.ball == i;
                        return GestureDetector(
                          onTap: () => setState(() {
                            my.ball = i;
                            audio.sfx('ui');
                            unawaited(_savePrefs());
                          }),
                          child: Container(
                            width: 72,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: on ? const Color(0x333BD0FF) : const Color(0x14FFFFFF),
                              border: Border.all(color: on ? const Color(0xFFFFD86B) : const Color(0x22FFFFFF), width: on ? 2 : 1),
                            ),
                            child: Column(children: <Widget>[
                              Expanded(child: Image.asset('${_a}balls/b$i.webp', cacheWidth: 112)),
                              Text(kBmBallN[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ] else
                  Text(launch.tx('زمین و توپ را میزبان انتخاب می‌کند', 'The host picks the field and the ball'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99EAF6FF), fontSize: 12)),
                const SizedBox(height: 20),
                Center(
                  child: waiting
                      ? Column(children: <Widget>[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(launch.tx('در انتظار حریف…', 'Waiting for the opponent…'),
                              style: const TextStyle(color: Color(0xCCEAF6FF), fontSize: 13)),
                        ])
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC23A),
                            foregroundColor: const Color(0xFF1A1200),
                            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          onPressed: () {
                            audio.sfx('ui');
                            unawaited(_savePrefs());
                            if (online) {
                              _sendSetup();
                            } else {
                              _startOffline();
                            }
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(online ? launch.tx('آماده‌ام', 'READY') : launch.tx('شروع بازی', 'START MATCH')),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: on ? const Color(0xFFFFC23A) : const Color(0x1AFFFFFF),
          border: Border.all(color: on ? const Color(0xFFFFD86B) : const Color(0x22FFFFFF)),
        ),
        child: Text(label,
            style: TextStyle(color: on ? const Color(0xFF1A1200) : Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.text, required this.big});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 34 : 26, vertical: big ? 10 : 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: big ? const LinearGradient(colors: <Color>[Color(0xFFFFD86B), Color(0xFFFF9A3A)]) : null,
        color: big ? null : const Color(0xEB0A1230),
        border: Border.all(color: const Color(0xFF3BD0FF), width: 1.5),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x663BD0FF), blurRadius: 28)],
      ),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: big ? const Color(0xFF1A1200) : Colors.white, fontSize: big ? 38 : 17, fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE00A1230),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(width: 50, height: 50, child: Icon(icon, color: const Color(0xFF8FE6FF), size: 26)),
      ),
    );
  }
}

class _BmDialog extends StatelessWidget {
  const _BmDialog({required this.title, required this.actions});
  final String title;
  final List<(String, String, IconData)> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xF20A1230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(title, style: const TextStyle(color: Color(0xFFFFD86B), fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          for (final (String, String, IconData) a in actions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: a.$1 == 'continue'
                        ? const Color(0xFFFFC23A)
                        : a.$1 == 'leave'
                            ? const Color(0xFFD9364A)
                            : const Color(0xFF1C2550),
                    foregroundColor: a.$1 == 'continue' ? const Color(0xFF1A1200) : Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(a.$1),
                  icon: Icon(a.$3),
                  label: Text(a.$2),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
