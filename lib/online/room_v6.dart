// v0.6 in-room screen (owner reference room_screen_ref.webp, NEXORA neon purple / orange theme). Top to bottom:
//   1) header bar: game icon + badge, room name, spectators eye, player count, share, "..." menu
//   2) hero card: neon goal + ball, "گل" title, "تو این جمع داره بازی NEXORA شروع میشه", big "من آماده‌ام!" button
//   3) row of large round avatars with glowing rings + names (host labelled "مدیر"); host taps an avatar to tick
//      2-6 players for the match or to kick
//   4) chat list: small round avatar + rounded bubble (RTL text)
//   5) wide purple glowing action button (ورود به بازی / تیم و ترکیب)
//   6) bottom bar: "همین‌جا بنویس" field + like and gem reaction buttons
// RoomBody is pure (data + callbacks) so it can be snapshot-tested without a server; RoomScreen wires a RoomLink.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/shell.dart' show AppNav;
import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/supabase.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/v4.dart' show N;
import 'link.dart';
import 'online_match.dart' show ruleLabel;
import 'room_ui.dart' show VoiceBar;
import 'ui.dart';

const _purple = Color(0xff8a3dff), _purple2 = Color(0xff5b1fd6), _violetGlow = Color(0xffb57bff);
const _card = Color(0xf20c0a2c), _card2 = Color(0xf2120c3a);

/// One member as the room body shows it.
class RoomMember {
  final String uid, name;
  final String? avatar, url;
  final bool player, host, ready, online, talking, me;
  const RoomMember({
    required this.uid,
    required this.name,
    this.avatar,
    this.url,
    this.player = false,
    this.host = false,
    this.ready = false,
    this.online = true,
    this.talking = false,
    this.me = false,
  });
}

class RoomBody extends StatefulWidget {
  final String name, code;
  final List<RoomMember> members;
  final List<ChatMsg> chat;
  final String me;
  final List<String> picks;
  final bool isHost, playing, voice;
  final int spectators, readyCount;
  final String heroLabel, actionLabel;
  final String? heroNote;
  final bool heroEnabled, heroDone;
  final List<String> tags;
  final Widget? voiceBar;
  final ValueListenable<(String, String, int)?>? reaction;
  final VoidCallback onHero, onAction, onShare, onMenu;
  final void Function(RoomMember m) onAvatar;
  final void Function(String text) onSend;
  final void Function(String kind) onReact;
  final int countdown;
  const RoomBody({
    super.key,
    required this.name,
    required this.code,
    required this.members,
    required this.chat,
    required this.me,
    required this.picks,
    required this.isHost,
    required this.playing,
    required this.spectators,
    required this.readyCount,
    required this.heroLabel,
    required this.actionLabel,
    required this.heroEnabled,
    required this.onHero,
    required this.onAction,
    required this.onShare,
    required this.onMenu,
    required this.onAvatar,
    required this.onSend,
    required this.onReact,
    this.heroNote,
    this.heroDone = false,
    this.voice = false,
    this.tags = const [],
    this.voiceBar,
    this.reaction,
    this.countdown = 0,
  });
  @override
  State<RoomBody> createState() => _RoomBodyState();
}

class _RoomBodyState extends State<RoomBody> {
  final ctl = TextEditingController();
  final _float = <(String, int, double)>[]; // kind, seq, x jitter
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.reaction?.addListener(_onRx);
    ctl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(RoomBody o) {
    super.didUpdateWidget(o);
    if (o.reaction != widget.reaction) {
      o.reaction?.removeListener(_onRx);
      widget.reaction?.addListener(_onRx);
    }
  }

  @override
  void dispose() {
    widget.reaction?.removeListener(_onRx);
    ctl.dispose();
    super.dispose();
  }

  void _onRx() {
    final r = widget.reaction?.value;
    if (r == null || !mounted) return;
    final s = ++_seq;
    setState(() => _float.add((r.$1, s, math.Random().nextDouble())));
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _float.removeWhere((e) => e.$2 == s));
    });
  }

  void _send() {
    final t = ctl.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    ctl.clear();
  }

  RoomMember? _by(String uid) => widget.members.where((m) => m.uid == uid).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), kb = MediaQuery.viewInsetsOf(context).bottom;
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: const Color(0xff07051c),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: _RoomBg()),
          Padding(
            padding: EdgeInsets.only(top: ins.top + 6, bottom: math.max(kb, ins.bottom) + 8),
            child: Column(
              children: [
                _header(),
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _hero(w)),
                if (widget.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      textDirection: TextDirection.rtl,
                      spacing: 6,
                      runSpacing: 4,
                      children: [for (final t in widget.tags) _Tag(t)],
                    ),
                  ),
                const SizedBox(height: 10),
                _avatars(),
                if (widget.voiceBar != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: widget.voiceBar),
                const SizedBox(height: 6),
                Expanded(child: _chatList()),
                Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: _actionBtn()),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _bottomBar()),
              ],
            ),
          ),
          // floating reactions
          for (final f in _float)
            Positioned(
              key: ValueKey('rx${f.$2}'),
              right: 40 + f.$3 * 60,
              bottom: ins.bottom + 70,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, c) => Opacity(
                    opacity: (1 - v).clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(math.sin(v * 6) * 10, -v * 220),
                      child: Transform.scale(scale: .7 + v * .6, child: c),
                    ),
                  ),
                  child: Icon(
                    f.$1 == 'gem' ? Icons.diamond_rounded : Icons.thumb_up_alt_rounded,
                    size: 34,
                    color: f.$1 == 'gem' ? _violetGlow : N.amber,
                    shadows: const [Shadow(color: N.orange, blurRadius: 16)],
                  ),
                ),
              ),
            ),
          if (widget.countdown > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0x9907051c),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tTitle(fa(widget.countdown), size: 96, shadows: const [Shadow(color: N.orange, blurRadius: 30)]),
                        tBold('بازی شروع می‌شود', size: 16, color: N.amber),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- 1) header ----------------
  Widget _header() {
    Widget ic(IconData i, VoidCallback? on, {String? n}) => Press(
      onTap: on,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, color: Colors.white, size: 25),
            if (n != null) ...[const SizedBox(width: 4), T(n, size: 15, family: F.num, weight: 800)],
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [_card2, _card]),
        border: Border.all(color: const Color(0x55b57bff)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            // game icon + badge
            SizedBox(
              width: 50,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned(
                    left: 0,
                    top: 4,
                    child: Icon(
                      Icons.sports_esports_rounded,
                      size: 36,
                      color: _violetGlow,
                      shadows: [Shadow(color: _purple, blurRadius: 14)],
                    ),
                  ),
                  if (widget.readyCount > 0)
                    Positioned(
                      left: 28,
                      top: -2,
                      child: Container(
                        width: 19,
                        height: 19,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xffff3d5a)),
                        child: T('${widget.readyCount}', size: 11, family: F.num, weight: 800),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(child: T(widget.name, size: 17, weight: 800, lines: 1)),
            ic(Icons.visibility_outlined, null, n: widget.spectators > 0 ? '${widget.spectators}' : null),
            ic(Icons.group_outlined, null, n: '${widget.members.where((m) => m.player).length}'),
            ic(Icons.ios_share_rounded, widget.onShare),
            ic(Icons.more_horiz_rounded, widget.onMenu),
          ],
        ),
      ),
    );
  }

  // ---------------- 2) hero ----------------
  Widget _hero(double w) {
    final h = (w * .62).clamp(220.0, 300.0);
    return Container(
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x99ff8a2a), width: 1.4),
        boxShadow: const [BoxShadow(color: Color(0x40ff6a2a), blurRadius: 22)],
        gradient: const RadialGradient(center: Alignment(0, -.3), radius: 1.1, colors: [Color(0xff2a0f55), Color(0xff0c0726)]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _GoalPainter())),
          ),
          Positioned(
            left: w * .15,
            top: h * .38,
            child: Img(ballImg(0), w: h * .19, h: h * .19),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * .07,
            child: Center(
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xffffe08a), Color(0xffff9a2a), Color(0xffff4f9a)],
                ).createShader(r),
                child: Text(
                  'گل',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: F.fa,
                    fontWeight: FontWeight.w900,
                    fontSize: h * .30,
                    height: 1,
                    color: Colors.white,
                    shadows: const [Shadow(color: Color(0xccff7a2a), blurRadius: 24)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const T(
                  'تو این جمع داره بازی NEXORA شروع میشه',
                  size: 17,
                  weight: 800,
                  align: TextAlign.center,
                  lines: 2,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
                if (widget.heroNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: T(widget.heroNote!, size: 11, color: const Color(0xffd9c8ff), align: TextAlign.center, lines: 1),
                  ),
                const SizedBox(height: 8),
                _GlowButton(
                  label: widget.heroLabel,
                  enabled: widget.heroEnabled,
                  done: widget.heroDone,
                  onTap: widget.onHero,
                  colors: const [Color(0xffffc46a), Color(0xffff8a2a), Color(0xffff5a3d)],
                  glow: N.orange,
                  width: w * .62,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 3) avatars ----------------
  Widget _avatars() {
    // reference order: the host sits at the end of the RTL row (far left)
    final list = [...widget.members.where((m) => !m.host), ...widget.members.where((m) => m.host)];
    return SizedBox(
      height: 104,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final m = list[i], pick = widget.picks.indexOf(m.uid);
            final ring = m.talking
                ? C.sky
                : m.player
                ? N.amber
                : _violetGlow;
            return Press(
              onTap: () => widget.onAvatar(m),
              child: SizedBox(
                width: 74,
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: pick >= 0 ? C.green : ring, width: 2.6),
                            boxShadow: [BoxShadow(color: (pick >= 0 ? C.green : ring).withValues(alpha: .55), blurRadius: m.talking || pick >= 0 ? 16 : 10)],
                          ),
                          child: Opacity(
                            opacity: m.online ? 1 : .5,
                            child: Avatar(avatar: m.avatar, url: m.url, size: 62, ring: Colors.transparent),
                          ),
                        ),
                        Positioned(
                          top: -4,
                          right: -4,
                          child: AnimatedScale(
                            scale: pick >= 0 ? 1 : 0,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutBack,
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: C.green,
                                border: Border.all(color: const Color(0xff07051c), width: 2),
                              ),
                              child: T(pick >= 0 ? fa(pick + 1) : '', size: 11, color: const Color(0xff05201a), weight: 800),
                            ),
                          ),
                        ),
                        if (m.ready && !m.host)
                          const Positioned(
                            bottom: 0,
                            left: 0,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: C.green,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    T(
                      m.host
                          ? 'مدیر'
                          : m.me
                          ? 'من'
                          : m.name,
                      size: 12,
                      weight: 800,
                      color: m.host
                          ? N.amber
                          : m.me
                          ? const Color(0xffffd9a8)
                          : Colors.white,
                      lines: 1,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------- 4) chat ----------------
  Widget _chatList() {
    final data = widget.chat.reversed.toList();
    if (data.isEmpty) return const Center(child: T('هنوز پیامی نیست؛ سلام کن!', size: 12, color: C.dim2));
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final c = data[i], m = _by(c.uid), mine = c.uid == widget.me;
        return TweenAnimationBuilder<double>(
          key: ValueKey(c.id),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (_, v, ch) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: ch),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Directionality(
              textDirection: TextDirection.ltr, // reference: avatar on the left, bubble beside it
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: mine ? N.amber : _violetGlow, width: 1.4),
                    ),
                    child: Avatar(avatar: m?.avatar, url: m?.url, size: 38, ring: Colors.transparent),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: mine ? const Color(0xcc3a1a2a) : const Color(0xcc1c1640),
                        border: Border.all(color: mine ? const Color(0x55ff8a2a) : const Color(0x406d5bff)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!mine && m != null) T(m.host ? '${m.name} · مدیر' : m.name, size: 10, color: N.amber, lines: 1),
                          T(c.text, size: 14, weight: 700, align: TextAlign.right),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------- 5) action ----------------
  Widget _actionBtn() => _GlowButton(
    label: widget.actionLabel,
    icon: widget.playing ? Icons.play_arrow_rounded : Icons.groups_2_rounded,
    enabled: true,
    onTap: widget.onAction,
    colors: const [Color(0xff9b4dff), _purple, _purple2],
    glow: _purple,
    height: 52,
  );

  // ---------------- 6) bottom bar ----------------
  Widget _bottomBar() {
    Widget round(IconData i, Color c, VoidCallback on) => Press(
      onTap: on,
      child: Container(
        width: 50,
        height: 50,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _card2,
          border: Border.all(color: c.withValues(alpha: .55)),
          boxShadow: [BoxShadow(color: c.withValues(alpha: .25), blurRadius: 10)],
        ),
        child: Icon(i, color: Colors.white, size: 25),
      ),
    );
    final has = ctl.text.trim().isNotEmpty;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctl,
              maxLength: 200,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: ts(size: 14, family: F.fa),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'همین‌جا بنویس',
                hintTextDirection: TextDirection.rtl,
                hintStyle: ts(size: 14, color: C.dim2, family: F.fa),
                filled: true,
                fillColor: _card,
                prefixIcon: AnimatedOpacity(
                  opacity: has ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IconButton(
                    onPressed: has ? _send : null,
                    icon: const Icon(Icons.send_rounded, color: N.amber, textDirection: TextDirection.rtl),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0x55b57bff)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0x55b57bff)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: N.orange),
                ),
              ),
            ),
          ),
          round(Icons.thumb_up_alt_rounded, N.amber, () => widget.onReact('like')),
          round(Icons.diamond_outlined, _violetGlow, () => widget.onReact('gem')),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String s;
  const _Tag(this.s);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0x331c1640),
      border: Border.all(color: const Color(0x44ff8a2a)),
    ),
    child: T(s, size: 11, color: const Color(0xffffd9a8)),
  );
}

/// Big glowing pill button with a press-scale and a soft enabled/disabled cross-fade.
class _GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled, done;
  final VoidCallback onTap;
  final List<Color> colors;
  final Color glow;
  final double? width;
  final double height;
  const _GlowButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.colors,
    required this.glow,
    this.icon,
    this.done = false,
    this.width,
    this.height = 54,
  });
  @override
  Widget build(BuildContext context) {
    final cs = done ? const [Color(0xff5dffbf), Color(0xff16b77a), Color(0xff0a6b4a)] : colors;
    return Press(
      onTap: enabled ? onTap : null,
      scaleTo: .96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2.6),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: enabled ? cs : const [Color(0xff2a2550), Color(0xff1c1840), Color(0xff15122f)],
          ),
          border: Border.all(color: enabled ? Colors.white.withValues(alpha: .35) : const Color(0x33ffffff), width: 1.2),
          boxShadow: enabled ? [BoxShadow(color: (done ? C.green : glow).withValues(alpha: .6), blurRadius: 22, spreadRadius: 1)] : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            T(label, size: 18, weight: 800, color: enabled ? Colors.white : C.dim, lines: 1),
            if (icon != null) ...[const SizedBox(width: 8), Icon(icon, color: enabled ? Colors.white : C.dim, size: 22)],
          ],
        ),
      ),
    );
  }
}

/// Neon goal (orange posts, violet net) on a pitch glow; baked by its RepaintBoundary (never repaints).
class _GoalPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // pitch glow
    c.drawRect(
      Offset(0, h * .55) & Size(w, h * .45),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0x553a1a7a)],
        ).createShader(Offset(0, h * .55) & Size(w, h * .45)),
    );
    final l = w * .12, r = w * .88, t = h * .08, b = h * .56, d = h * .07;
    final net = Paint()
      ..color = const Color(0x55b57bff)
      ..strokeWidth = 1;
    for (var i = 0; i <= 14; i++) {
      final x = l + (r - l) * i / 14;
      c.drawLine(Offset(x, t + d * .4), Offset(x + (x - w / 2) * -.04, b - d * .2), net);
    }
    for (var j = 0; j <= 7; j++) {
      final y = t + d * .4 + (b - t - d * .6) * j / 7;
      c.drawLine(Offset(l + 4, y), Offset(r - 4, y), net);
    }
    final post = Path()
      ..moveTo(l, b)
      ..lineTo(l, t)
      ..lineTo(r, t)
      ..lineTo(r, b);
    c.drawPath(
      post,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = const Color(0x88ff7a2a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    c.drawPath(
      post,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xffffb35c),
    );
    c.drawLine(
      Offset(l - w * .06, b),
      Offset(r + w * .06, b),
      Paint()
        ..color = const Color(0x88ff8a2a)
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class _RoomBg extends StatelessWidget {
  const _RoomBg();
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/g/v6/bg_stadium.webp', fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
        const DecoratedBox(decoration: BoxDecoration(color: Color(0xb307051c))),
      ],
    ),
  );
}

// ======================================================================= live wiring
/// The in-room screen over a [RoomLink] (replaces the v0.5 LobbyScreen).
class RoomScreen extends StatefulWidget {
  final RoomLink link;
  final VoidCallback onLeave, onWatch;
  final Widget Function(BuildContext ctx, RoomLink link)? settings;
  const RoomScreen({super.key, required this.link, required this.onLeave, required this.onWatch, this.settings});
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  RoomLink get link => widget.link;
  String? busy;
  int count = 0;
  Timer? _cd;
  bool _auto = false;
  String _seatTry = '';

  Future<void> run(String key, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      await fn();
      link.ping();
      await link.refresh();
      if (ok != null) toast(ok, 'ok');
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  void dispose() {
    _cd?.cancel();
    super.dispose();
  }

  void _checkAuto(bool auto, bool isHost) {
    if (auto == _auto) return;
    _auto = auto;
    _cd?.cancel();
    if (!auto) {
      if (count != 0) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => count = 0) : null);
      return;
    }
    var n = 3;
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => count = n) : null);
    sfx(Snd.tick);
    _cd = Timer.periodic(const Duration(seconds: 1), (t) {
      n--;
      if (n > 0) {
        setState(() => count = n);
        sfx(Snd.tick);
        buzz();
        return;
      }
      t.cancel();
      setState(() => count = 0);
      final room = link.room;
      if (isHost && room != null) run('start', () async => rpc('start_match', {'p_room': room.s('id')}));
    });
  }

  /// A picked member (first two in the host's list) takes a free seat on their own device (existing take_seat RPC).
  void _autoSeat(Rec room, List<List<Rec?>> seats, bool amPlayer) {
    final i = link.picks.indexOf(link.me);
    if (i < 0 || i > 1 || amPlayer || room.s('status') != 'waiting' || busy != null) return;
    final t = seats[i][0] == null ? i : (seats[1 - i][0] == null ? 1 - i : -1);
    final key = '${link.picks.join(',')}:$t';
    if (t < 0 || key == _seatTry) return;
    _seatTry = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      toast('مدیر تو را برای بازی انتخاب کرد', 'ok');
      run('seat', () async => rpc('take_seat', {'p_room': room.s('id'), 'p_team': t, 'p_slot': 0}));
    });
  }

  Future<void> _avatar(RoomMember m, Rec room, bool isHost, bool playing) async {
    if (!isHost || playing) {
      if (!m.me) AppNav.openProfile(m.uid);
      return;
    }
    final picked = link.picks.contains(m.uid);
    final r = await showCard<String>(
      context,
      accent: N.orange,
      child: (cc) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Avatar(avatar: m.avatar, url: m.url, size: 72, ring: N.amber),
            ),
            const SizedBox(height: 8),
            tBold(m.host ? '${m.name} (مدیر)' : m.name, size: 16, align: TextAlign.center),
            const SizedBox(height: 4),
            T('انتخاب‌شده‌ها: ${fa(link.picks.length)} از ۶ · دو نفر اول بازی می‌کنند (۱ به ۱)', size: 11, color: C.dim, align: TextAlign.center),
            const SizedBox(height: 14),
            Btn(
              picked ? 'برداشتن تیک' : 'تیک برای بازی',
              colors: picked ? G.dark : G.green,
              disabled: !picked && link.picks.length >= 6,
              onTap: () => Navigator.pop(cc, 'pick'),
            ),
            if (!m.me) ...[const SizedBox(height: 8), Btn('مشاهده پروفایل', colors: G.dark, onTap: () => Navigator.pop(cc, 'profile'))],
            if (!m.me) ...[const SizedBox(height: 8), Btn('اخراج از اتاق', colors: G.red, onTap: () => Navigator.pop(cc, 'kick'))],
            const SizedBox(height: 8),
            Btn('بستن', small: true, colors: G.dark, onTap: () => Navigator.pop(cc)),
          ],
        ),
      ),
    );
    if (r == 'profile') {
      AppNav.openProfile(m.uid);
    } else if (r == 'pick') {
      final p = [...link.picks];
      picked ? p.remove(m.uid) : p.add(m.uid);
      link.setPicks(p);
      buzz();
    } else if (r == 'kick') {
      run('kick', () async {
        await rpc('kick', {'p_room': room.s('id'), 'p_user': m.uid});
        link.setPicks([...link.picks]..remove(m.uid));
      }, 'بازیکن اخراج شد');
    }
  }

  void _menu(Rec room, bool isHost, bool playing, bool amPlayer) => showCard<void>(
    context,
    accent: _purple,
    child: (cc) => Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tBold(room.s('name'), size: 16, align: TextAlign.center),
          T('کد اتاق: ${room.s('code')}', size: 12, color: C.dim, align: TextAlign.center),
          const SizedBox(height: 12),
          if (isHost && !playing && room.str('tournament_match_id') == null && widget.settings != null) ...[
            Btn(
              'تنظیمات اتاق',
              colors: G.violet,
              onTap: () {
                Navigator.pop(cc);
                showSheet(context, title: 'تنظیمات اتاق', en: 'ROOM SETTINGS', height: .8, child: (ctx) => widget.settings!(ctx, link));
              },
            ),
            const SizedBox(height: 8),
          ],
          if (amPlayer && !playing) ...[
            Btn(
              'فقط تماشا',
              colors: G.dark,
              onTap: () {
                Navigator.pop(cc);
                run('spec', () async => rpc('spectate', {'p_room': room.s('id')}));
              },
            ),
            const SizedBox(height: 8),
          ],
          Btn(
            'خروج از اتاق',
            colors: G.red,
            onTap: () {
              Navigator.pop(cc);
              widget.onLeave();
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([link, link.voice]),
    builder: (context, _) {
      final room = link.room;
      if (room == null)
        return const Scaffold(
          backgroundColor: Color(0xff07051c),
          body: Center(child: Spinner(size: 36)),
        );
      final me = link.me, host = room.s('host'), n = teamSize(room.s('mode', '1v1'));
      final seats = [List<Rec?>.filled(n, null), List<Rec?>.filled(n, null)];
      for (final p in link.players) {
        final t = p.i('team', -1), sl = p.m['slot'] is num ? p.i('slot') : -1;
        if (p.s('role') == 'player' && (t == 0 || t == 1) && sl >= 0 && sl < n) seats[t][sl] = p;
      }
      final meP = link.players.where((p) => p.s('user_id') == me).firstOrNull;
      final isHost = host == me, amPlayer = meP?.s('role') == 'player';
      final full = seats.every((s) => s.every((x) => x != null));
      final notReady = link.players.where((p) => p.s('role') == 'player' && !p.b('ready') && p.s('user_id') != host).toList();
      final playing = room.s('status') == 'playing';
      final block = link.protoBlock;
      final canStart = isHost && full && notReady.isEmpty && room.s('status') == 'waiting' && block == null;
      final kind = room.s('kind', 'casual');
      final quickKind = kind == 'quick' || kind == 'arena';
      _checkAuto(quickKind && room.s('status') == 'waiting' && full && notReady.isEmpty && block == null, isHost);
      _autoSeat(room, seats, amPlayer);
      final speaking = link.voice.speaking.toSet();
      final members = [
        for (final p in link.players)
          () {
            final uid = p.s('user_id'), pr = p.rec('profiles');
            return RoomMember(
              uid: uid,
              name: pr.s('username', '…'),
              avatar: link.teamFor(uid) ?? pr.str('equipped_disc') ?? pr.str('avatar'),
              url: link.teamFor(uid) != null ? null : pr.str('avatar_url'),
              player: p.s('role') == 'player',
              host: uid == host,
              ready: p.b('ready'),
              online: link.online.containsKey(uid),
              talking: speaking.contains(uid),
              me: uid == me,
            );
          }(),
      ];
      final players = link.players.where((p) => p.s('role') == 'player').length;
      String hero;
      String? note;
      var enabled = busy == null, done = false;
      VoidCallback onHero = () {};
      if (playing) {
        hero = 'تماشای بازی زنده';
        onHero = widget.onWatch;
      } else if (quickKind) {
        hero = full ? 'آماده‌ی شروع…' : 'در جستجوی حریف…';
        note = '${fa(players)}/${fa(n * 2)} بازیکن';
        enabled = false;
      } else if (isHost) {
        hero = busy == 'start' ? 'در حال شروع…' : 'شروع بازی!';
        enabled = canStart && busy == null;
        note =
            block ??
            (!full
                ? (link.picks.length < 2 ? 'روی آواتارها بزن و ۲ تا ۶ بازیکن را تیک بزن' : 'منتظر نشستن بازیکن‌های انتخاب‌شده…')
                : notReady.isNotEmpty
                ? 'منتظر آماده شدن ${fa(notReady.length)} بازیکن…'
                : null);
        onHero = () => run('start', () async {
          await rpc('start_match', {'p_room': room.s('id')});
          buzz('heavy');
        });
      } else if (amPlayer) {
        done = meP!.b('ready');
        hero = done ? 'آماده‌ام ✓' : 'من آماده‌ام!';
        onHero = () => run('ready', () async {
          await rpc('set_ready', {'p_room': room.s('id'), 'p_ready': !meP.b('ready')});
          sfx(Snd.ready);
          buzz('medium');
        });
      } else {
        hero = 'من آماده‌ام!';
        final free = seats[0][0] == null ? 0 : (seats[1][0] == null ? 1 : -1);
        note = free < 0 ? 'جایگاه‌ها پر است؛ تماشاچی هستی' : null;
        enabled = free >= 0 && busy == null;
        onHero = () => run('seat', () async {
          await rpc('take_seat', {'p_room': room.s('id'), 'p_team': free, 'p_slot': 0});
          await rpc('set_ready', {'p_room': room.s('id'), 'p_ready': true});
          sfx(Snd.ready);
        });
      }
      final st = room.rec('settings');
      return RoomBody(
        name: room.s('name'),
        code: room.s('code'),
        members: members,
        chat: link.chat,
        me: me,
        picks: link.picks,
        isHost: isHost,
        playing: playing,
        spectators: link.players.where((p) => p.s('role') != 'player').length,
        readyCount: link.players.where((p) => p.s('role') == 'player' && (p.b('ready') || p.s('user_id') == host)).length,
        heroLabel: hero,
        heroNote: note,
        heroEnabled: enabled,
        heroDone: done,
        actionLabel: playing ? 'ورود به بازی' : 'تیم و ترکیب',
        tags: [
          ruleLabel(st),
          // v9: matchmade rooms play the host's equipped pitch (hostFieldBall), not the server's default setting
          if (const {'casual', 'social'}.contains(room.s('kind', 'casual'))) kFields[st.i('field').clamp(0, kFields.length - 1)].name,
          room.b('ranked') ? 'رتبه‌ای' : 'دوستانه',
          if (room.b('is_private')) 'خصوصی',
          if (link.rtt != null) 'پینگ ${fa(link.rtt!)}',
        ],
        voiceBar: room.b('voice') ? VoiceBar(link: link, enabled: true) : null,
        reaction: link.reaction,
        countdown: count,
        onHero: onHero,
        onAction: playing ? widget.onWatch : AppNav.openTeam,
        onShare: () async {
          await Clipboard.setData(ClipboardData(text: 'بیا تو اتاق «${room.s('name')}» در NEXORA بازی کنیم! کد اتاق: ${room.s('code')}'));
          toast('دعوت‌نامه و کد اتاق کپی شد: ${room.s('code')}', 'ok');
        },
        onMenu: () => _menu(room, isHost, playing, amPlayer),
        onAvatar: (m) => _avatar(m, room, isHost, playing),
        onSend: (t) {
          link.sendChat(t);
          buzz();
        },
        onReact: (k) {
          link.react(k);
          buzz();
        },
      );
    },
  );
}
