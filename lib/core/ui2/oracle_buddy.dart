import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/music_service.dart';
import '../backend/backend_gateway.dart';
import '../backend/supabase_backend.dart';
import '../settings/app_settings.dart';
import '../storage/local_store.dart';
import '../../worlds/oracle_core/persona/oracle_persona.dart';
import '../../worlds/oracle_core/persona/oracle_persona_store.dart';
import '../../worlds/oracle_core/persona/oracle_tour.dart';
import '../online/online_service.dart';
import '../profile/profile_service.dart';
import 'oracle_lines.dart';

/// App-wide events the corner ORACLE reacts to (wins, losses, purchases…).
class OracleBus {
  OracleBus._();
  static final StreamController<String> _c = StreamController<String>.broadcast();
  static Stream<String> get stream => _c.stream;
  static void emit(String event) {
    if (!_c.isClosed) _c.add(event);
  }

  /// Any touch anywhere (idle detection).
  static DateTime lastTouch = DateTime.now();
}

enum BuddyMood { idle, wave, talk, sulk, sleep, wink, laugh, confused, shocked, excited }

String _sprite(BuddyMood m) => switch (m) {
      BuddyMood.idle => 'assets/characters/oracle/moods/sheetB_01.webp',
      BuddyMood.wave => 'assets/characters/oracle/moods/wave.webp',
      BuddyMood.talk => 'assets/characters/oracle/moods/sheetB_06.webp',
      BuddyMood.sulk => 'assets/characters/oracle/moods/sulk.webp',
      BuddyMood.sleep => 'assets/characters/oracle/moods/sleepy.webp',
      BuddyMood.wink => 'assets/characters/oracle/moods/wink.webp',
      BuddyMood.laugh => 'assets/characters/oracle/moods/laugh.webp',
      BuddyMood.confused => 'assets/characters/oracle/moods/confused.webp',
      BuddyMood.shocked => 'assets/characters/oracle/moods/shocked.webp',
      BuddyMood.excited => 'assets/characters/oracle/moods/excited.webp',
    };

/// The mischievous corner ORACLE: lives above every page except games, teases, sulks until apologised to, falls
/// asleep and snores until poked, winks, laughs, gets confused, reacts to wins/losses/purchases/idle time.
/// Drag to move (position is remembered), long-press to open ORACLE chat, double-tap to minimise to an orb.
class OracleBuddy extends ConsumerStatefulWidget {
  const OracleBuddy({super.key, this.router});
  final GoRouter? router;

  @override
  ConsumerState<OracleBuddy> createState() => _OracleBuddyState();
}

class _OracleBuddyState extends ConsumerState<OracleBuddy> with TickerProviderStateMixin {
  static const String _kPos = 'oracle_buddy.pos';
  static const String _kMin = 'oracle_buddy.min';
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();
  late final AnimationController _squash = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();
  final math.Random _rng = math.Random();
  BuddyMood _mood = BuddyMood.wave;
  String? _bubble;
  bool _needsApology = false;
  bool _minimized = false;
  Offset _pos = const Offset(.82, .70); // fractional (centre of the buddy)
  Timer? _tick, _bubbleTimer, _moodTimer;
  StreamSubscription<String>? _events;
  DateTime _lastAct = DateTime.now();
  int _aiCounter = 0;
  bool _aiBusy = false;
  // guided tour
  String? _tourSection;
  List<OracleTourStep> _tourSteps = const <OracleTourStep>[];
  String _lastPath = '';
  Timer? _tourTimer;

  bool get _fa => Localizations.maybeLocaleOf(context)?.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    final String? p = LocalStore.instance.getString(_kPos);
    if (p != null && p.contains(',')) {
      final List<String> xy = p.split(',');
      _pos = Offset(double.tryParse(xy[0]) ?? .82, double.tryParse(xy[1]) ?? .7);
    }
    _minimized = LocalStore.instance.getBool(_kMin) ?? false;
    _events = OracleBus.stream.listen(_onEvent);
    _tick = Timer.periodic(const Duration(seconds: 7), (_) => _onTick());
    OraclePersonaStore.loadCached();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final OnlineService o = ref.read(onlineProvider);
      unawaited(OraclePersonaStore.refresh(o.client));
      unawaited(OracleTourStore.pullCloud(o.client, o.client?.auth.currentUser?.id));
      _loginGreeting();
      _onRoute();
    });
    widget.router?.routerDelegate.addListener(_onRoute);
    OracleTourStore.replayTick.addListener(_onReplay);
  }

  String get _path {
    try {
      // The top-most page, including pages pushed with context.push (the base `uri` stays on /hub for those, so the
      // guided tour used to think every screen was the home page and showed the home tour on top of it).
      final RouteMatchList? cfg = widget.router?.routerDelegate.currentConfiguration;
      if (cfg == null || cfg.isEmpty) return '';
      return Uri.parse(cfg.last.matchedLocation).path;
    } catch (_) {
      return '';
    }
  }

  String? get _uid => ref.read(onlineProvider).client?.auth.currentUser?.id;

  void _onRoute() {
    final String p = _path;
    if (p == _lastPath) return;
    _lastPath = p;
    _tourTimer?.cancel();
    if (_tourSection != null && mounted) setState(() => _tourSection = null);
    _tourTimer = Timer(const Duration(milliseconds: 1100), () => _maybeTour(p));
  }

  void _onReplay() {
    _lastPath = '';
    _onRoute();
  }

  void _maybeTour(String path, {String? section}) {
    if (!mounted || MusicService.instance.inGame || path != _path) return;
    final String? sec = section ?? OraclePersonaTour.sectionForPath(path);
    if (sec == null || OracleTourStore.seen(_uid).contains(sec)) return;
    final List<OracleTourStep> steps = OraclePersona.instance.tourSteps(sec);
    if (steps.isEmpty) return;
    setState(() {
      _tourSection = sec;
      _tourSteps = steps;
      _bubble = null;
    });
  }

  void _tourDone() {
    final String? sec = _tourSection;
    if (sec == null) return;
    unawaited(OracleTourStore.markSeen(_uid, sec, client: ref.read(onlineProvider).client));
    setState(() => _tourSection = null);
    if (sec == 'home') {
      Future<void>.delayed(const Duration(milliseconds: 350), () => _maybeTour(_path, section: 'dock'));
    }
  }

  @override
  void dispose() {
    widget.router?.routerDelegate.removeListener(_onRoute);
    OracleTourStore.replayTick.removeListener(_onReplay);
    _tourTimer?.cancel();
    _tick?.cancel();
    _bubbleTimer?.cancel();
    _moodTimer?.cancel();
    _events?.cancel();
    _bob.dispose();
    _squash.dispose();
    _fx.dispose();
    super.dispose();
  }

  bool get _hiddenNow => MusicService.instance.inGame || !ref.read(settingsProvider).oracleBuddy;

  void _setMood(BuddyMood m, {Duration? hold}) {
    if (!mounted) return;
    _moodTimer?.cancel();
    if (m != _mood) {
      HapticFeedback.selectionClick();
      _squash.forward(from: 0);
    }
    setState(() => _mood = m);
    if (hold != null) {
      _moodTimer = Timer(hold, () {
        if (mounted && !_needsApology && _mood != BuddyMood.sleep) setState(() => _mood = BuddyMood.idle);
      });
    }
  }

  void _show(String text, {Duration d = const Duration(seconds: 5)}) {
    if (!mounted || !ref.read(settingsProvider).oracleTalk || _minimized) return;
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    _bubbleTimer = Timer(d, () {
      if (mounted && !_needsApology) setState(() => _bubble = null);
    });
  }

  void _say(OracleTopic t, BuddyMood m, {Duration hold = const Duration(seconds: 5)}) {
    _setMood(m, hold: hold);
    _show(OracleLines.pick(t).of(_fa), d: hold);
  }

  void _onEvent(String e) {
    if (_hiddenNow) return;
    _lastAct = DateTime.now();
    if (_mood == BuddyMood.sleep) _setMood(BuddyMood.idle);
    switch (e) {
      case 'win':
        _say(OracleTopic.win, BuddyMood.excited);
      case 'loss':
        _say(OracleTopic.loss, _rng.nextBool() ? BuddyMood.laugh : BuddyMood.confused);
      case 'draw':
        _say(OracleTopic.draw, BuddyMood.wink);
      case 'spend':
        _say(OracleTopic.spend, BuddyMood.shocked);
    }
  }

  void _onTick() {
    if (!mounted || _hiddenNow || _minimized || _tourSection != null) return;
    final Duration idle = DateTime.now().difference(OracleBus.lastTouch);
    if (_needsApology) {
      if (_rng.nextInt(5) == 0) _show(OracleLines.pick(OracleTopic.sulk).of(_fa));
      return;
    }
    if (_mood == BuddyMood.sleep) {
      if (_rng.nextInt(3) == 0) _show(OracleLines.pick(OracleTopic.sleep).of(_fa), d: const Duration(seconds: 3));
      return;
    }
    if (idle > const Duration(seconds: 75)) {
      _goSleep();
      return;
    }
    if (idle > const Duration(seconds: 40) && _rng.nextInt(3) == 0) {
      if (!_persona('idle', BuddyMood.confused)) _say(OracleTopic.idle, BuddyMood.confused);
      return;
    }
    // A random antic roughly every 35-60 s.
    if (DateTime.now().difference(_lastAct) < Duration(seconds: 28 + _rng.nextInt(30))) return;
    _lastAct = DateTime.now();
    final int r = _rng.nextInt(100);
    if (r < 10) {
      _goSulk();
    } else if (r < 18) {
      _goSleep();
    } else if (r < 30) {
      _say(OracleTopic.wink, BuddyMood.wink, hold: const Duration(seconds: 3));
    } else if (r < 40) {
      _say(OracleTopic.laugh, BuddyMood.laugh);
    } else if (r < 48) {
      _say(OracleTopic.confused, BuddyMood.confused);
    } else if (r < 54) {
      _say(OracleTopic.shocked, BuddyMood.shocked, hold: const Duration(seconds: 3));
    } else if (r < 78) {
      const List<String> ctxs = <String>['enter', 'waiting', 'funny', 'tease', 'unexpected'];
      if (!_persona(ctxs[_rng.nextInt(ctxs.length)], _rng.nextBool() ? BuddyMood.talk : BuddyMood.wink)) _tease();
    } else {
      _tease();
    }
  }

  Future<void> _tease() async {
    _aiCounter++;
    // Every 4th tease: a fresh line from the online ORACLE (falls back to the local pool).
    if (_aiCounter % 4 == 0 && !_aiBusy) {
      final BackendGateway be = ref.read(backendProvider);
      if (be is SupabaseBackend) {
        _aiBusy = true;
        try {
          final Map<String, dynamic>? r = await be.oracleInvoke(<String, dynamic>{
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'user',
                'content': _fa
                    ? 'یک جمله‌ی خیلی کوتاه (حداکثر ۱۴ کلمه)، بامزه و شیطنت‌آمیز و مهربان برای سربه‌سر گذاشتن بازیکن بگو، با یک ایموجی. فقط خود جمله.'
                    : 'Write one very short (max 14 words) witty, playful, kind teasing line for the player, with one emoji. Only the line.',
              }
            ],
            'ctx': <String, dynamic>{'mode': 'chat', 'lang': _fa ? 'fa' : 'en', 'persona': OraclePersona.instance.aiContext('')},
          });
          final Object? m = r?['message'];
          final String line = m is Map ? '${m['content'] ?? ''}'.trim() : '';
          if (line.isNotEmpty && line.length < 160 && mounted) {
            _setMood(BuddyMood.talk, hold: const Duration(seconds: 6));
            _show(line, d: const Duration(seconds: 6));
            return;
          }
        } catch (_) {
          // local fallback below
        } finally {
          _aiBusy = false;
        }
      }
    }
    if (mounted) _say(OracleTopic.tease, _rng.nextBool() ? BuddyMood.talk : BuddyMood.wink, hold: const Duration(seconds: 6));
  }

  /// Random login greeting with the real display name (sometimes silent; the "Original" mix-up joke always admits it).
  Future<void> _loginGreeting() async {
    final String name = ref.read(profileProvider).username;
    final List<String> lines = OraclePersona.instance.loginGreeting(name);
    if (lines.isEmpty) {
      final int h = DateTime.now().hour;
      if (_rng.nextBool()) {
        _say(h >= 5 && h < 12 ? OracleTopic.greetMorning : (h >= 23 || h < 5) ? OracleTopic.greetNight : OracleTopic.returnBack,
            BuddyMood.wave);
      }
      return;
    }
    for (int i = 0; i < lines.length; i++) {
      if (!mounted || _hiddenNow) return;
      _setMood(i == 0 ? BuddyMood.excited : i == lines.length - 1 ? BuddyMood.laugh : BuddyMood.shocked,
          hold: const Duration(milliseconds: 3600));
      _show(lines[i], d: const Duration(milliseconds: 3600));
      _lastAct = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 3300));
    }
  }

  /// A persona line for [context] (cooldowns + no-repeat inside the persona engine). Returns false when silent.
  bool _persona(String context, BuddyMood m) {
    final String? l = OraclePersona.instance.spontaneous(context);
    if (l == null) return false;
    _setMood(m, hold: const Duration(seconds: 5));
    _show(l);
    return true;
  }

  void _goSulk() {
    _needsApology = true;
    _setMood(BuddyMood.sulk);
    _show(OracleLines.pick(OracleTopic.sulk).of(_fa), d: const Duration(seconds: 8));
  }

  void _goSleep() {
    _setMood(BuddyMood.sleep);
    _show(OracleLines.pick(OracleTopic.sleep).of(_fa), d: const Duration(seconds: 4));
  }

  void _apologise() {
    _needsApology = false;
    _say(OracleTopic.forgive, BuddyMood.excited);
  }

  void _onTap() {
    OracleBus.lastTouch = DateTime.now();
    _lastAct = DateTime.now();
    if (_needsApology) {
      _show(_fa ? 'اول عذرخواهی کن! 😤' : 'Apologise first! 😤', d: const Duration(seconds: 6));
      return;
    }
    if (_mood == BuddyMood.sleep) {
      _say(OracleTopic.wake, BuddyMood.shocked, hold: const Duration(seconds: 4));
      return;
    }
    _say(OracleTopic.poke, _rng.nextBool() ? BuddyMood.laugh : BuddyMood.wink, hold: const Duration(seconds: 4));
  }

  void _toggleMin() {
    setState(() => _minimized = !_minimized);
    LocalStore.instance.setBool(_kMin, _minimized);
    if (!_minimized) _say(OracleTopic.returnBack, BuddyMood.wave);
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings s = ref.watch(settingsProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: MusicService.instance.inGameListenable,
      builder: (BuildContext context, bool inGame, _) {
        if (inGame) return const SizedBox.shrink();
        if (_tourSection != null) {
          return OracleTourOverlay(key: ValueKey<String>(_tourSection!), steps: _tourSteps, onDone: _tourDone);
        }
        if (!s.oracleBuddy) return const SizedBox.shrink();
        final Size sz = MediaQuery.sizeOf(context);
        final EdgeInsets pad = MediaQuery.paddingOf(context);
        final double w = _minimized ? 46 : 86;
        final double cx = (_pos.dx * sz.width).clamp(w / 2 + 4, sz.width - w / 2 - 4);
        final double cy = (_pos.dy * sz.height).clamp(pad.top + w / 2 + 40, sz.height - pad.bottom - w / 2 - 80);
        final bool reduced = s.reducedMotion;
        final bool bubbleLeft = cx > sz.width / 2;
        return Stack(clipBehavior: Clip.none, children: <Widget>[
          if (_bubble != null && !_minimized)
            Positioned(
              top: cy - w / 2 - 8,
              left: bubbleLeft ? null : cx + w / 2 - 6,
              right: bubbleLeft ? sz.width - cx + w / 2 - 6 : null,
              child: _Bubble(
                text: _bubble!,
                apology: _needsApology,
                fa: _fa,
                onApologise: _apologise,
                maxWidth: math.min(240, sz.width * .62),
              ),
            ),
          Positioned(
            left: cx - w / 2,
            top: cy - w / 2,
            width: w,
            height: w * (_minimized ? 1 : 1.12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _minimized ? _toggleMin : _onTap,
              onDoubleTap: _minimized ? null : _toggleMin,
              onLongPress: () => widget.router?.push('/oracle'),
              onPanUpdate: (DragUpdateDetails d) {
                setState(() => _pos = Offset(
                    ((_pos.dx * sz.width + d.delta.dx) / sz.width).clamp(0.0, 1.0),
                    ((_pos.dy * sz.height + d.delta.dy) / sz.height).clamp(0.0, 1.0)));
              },
              onPanEnd: (_) {
                // snap to the nearest side so it never sits over the middle of the page
                setState(() => _pos = Offset(_pos.dx < .5 ? .08 : .92, _pos.dy));
                LocalStore.instance.setString(_kPos, '${_pos.dx},${_pos.dy}');
              },
              child: _minimized ? _orb() : _body(reduced),
            ),
          ),
        ]);
      },
    );
  }

  Widget _orb() => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: <Color>[Color(0xFF6FE8FF), Color(0xFF1B3D8F)]),
          boxShadow: <BoxShadow>[BoxShadow(color: const Color(0xFF39E6FF).withValues(alpha: .6), blurRadius: 14)],
        ),
        child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
      );

  Widget _body(bool reduced) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_bob, _squash, _fx]),
      builder: (BuildContext context, _) {
        final double t = _bob.value * 2 * math.pi;
        final bool asleep = _mood == BuddyMood.sleep;
        final double bob = reduced ? 0 : math.sin(t) * (asleep ? 2 : 5);
        final double sq = reduced ? 0 : math.sin(_squash.value * math.pi) * (1 - _squash.value) * .22;
        final double breathe = asleep && !reduced ? math.sin(t) * .03 : 0;
        final bool turned = _mood == BuddyMood.sulk;
        final double glow = .45 + .25 * math.sin(t * 1.5);
        final Color gc = switch (_mood) {
          BuddyMood.sulk => const Color(0xFFFF5A5A),
          BuddyMood.sleep => const Color(0xFF7A7CFF),
          BuddyMood.excited || BuddyMood.laugh => const Color(0xFFFFC857),
          _ => const Color(0xFF39E6FF),
        };
        return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: <Widget>[
          // glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: <Color>[gc.withValues(alpha: .38 * glow), gc.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, bob),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values((turned ? -1 : 1) * (1 + sq + breathe), 1 - sq * .8 + breathe, 1),
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduced ? 0 : 260),
                transitionBuilder: (Widget c, Animation<double> a) =>
                    FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: .86, end: 1).animate(a), child: c)),
                child: Image.asset(
                  _sprite(_mood),
                  key: ValueKey<BuddyMood>(_mood),
                  fit: BoxFit.contain,
                  cacheWidth: 220,
                  errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 48),
                ),
              ),
            ),
          ),
          if (asleep && !reduced) ..._zzz(),
          if (_mood == BuddyMood.sulk && !reduced) ..._puffs(),
        ]);
      },
    );
  }

  List<Widget> _zzz() {
    return <Widget>[
      for (int i = 0; i < 3; i++)
        Builder(builder: (BuildContext context) {
          final double p = (_fx.value + i / 3) % 1;
          return Positioned(
            right: -4 - p * 18,
            top: 4 - p * 34,
            child: Opacity(
              opacity: (1 - p).clamp(0.0, 1.0),
              child: Text('z',
                  style: TextStyle(
                      color: const Color(0xFFB9C2FF), fontSize: 12 + p * 12, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            ),
          );
        }),
    ];
  }

  List<Widget> _puffs() {
    return <Widget>[
      for (int i = 0; i < 3; i++)
        Builder(builder: (BuildContext context) {
          final double p = (_fx.value * 1.5 + i / 3) % 1;
          final double a = -math.pi / 2 + (i - 1) * .7;
          return Positioned(
            left: 36 + math.cos(a) * (20 + p * 22),
            top: 26 + math.sin(a) * (20 + p * 22),
            child: Opacity(
              opacity: (1 - p).clamp(0.0, 1.0),
              child: Container(
                width: 8 + p * 8,
                height: 8 + p * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == 1 ? const Color(0xFFFF5A5A).withValues(alpha: .8) : Colors.white.withValues(alpha: .75),
                ),
              ),
            ),
          );
        }),
    ];
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.apology, required this.fa, required this.onApologise, required this.maxWidth});
  final String text;
  final bool apology;
  final bool fa;
  final VoidCallback onApologise;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(text),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double v, Widget? c) =>
          Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .8 + .2 * v, child: c)),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: <Color>[Color(0xF2182A5E), Color(0xF22A1556)]),
            border: Border.all(color: apology ? const Color(0xFFFF7A7A) : const Color(0xFF39E6FF), width: 1),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x5539E6FF), blurRadius: 14)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
            if (apology) ...<Widget>[
              const SizedBox(height: 6),
              SizedBox(
                height: 30,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A7A), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: onApologise,
                  child: Text(fa ? 'ببخشید 🙏' : 'Sorry 🙏', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
