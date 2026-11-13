// Shared online building blocks — port of src/online/ui.tsx (Header, Skeleton, Empty, ErrorState, Badge, Card, Tabs, StatBars).
import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/util.dart';
import '../i18n/i18n.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class S {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24;
}

class TS {
  static const double title = 20, h = 16, body = 14, small = 12, cap = 11, tiny = 10;
}

Team teamOfAvatar(String? key) => TEAMS.firstWhere((t) => t.id == key || teamKey(t) == key, orElse: () => TEAMS[0]);
String discImgOf(String? key) => teamImg(teamKey(teamOfAvatar(key))) ?? TEAM_IMG['club00']!;

class AvatarO extends StatelessWidget {
  final String? avatar, url;
  final double size;
  final Color? ring;
  final bool dim;
  const AvatarO({super.key, this.avatar, this.url, this.size = 40, this.ring, this.dim = false});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? .5 : 1,
        child: Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring ?? C.cyan, width: 2), color: hex('#050816')),
          child: ClipOval(child: Img(url ?? discImgOf(avatar), w: size - 6, h: size - 6, fit: url != null ? BoxFit.cover : BoxFit.contain)),
        ),
      );
}

/// header with a 44pt back button (positioned at the top of a Stack)
class Header extends StatelessWidget {
  final String title;
  final String? en;
  final VoidCallback onBack;
  final Widget? right;
  final Color? accent;
  const Header({super.key, required this.title, this.en, required this.onBack, this.right, this.accent});
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Positioned(
      left: 0, right: 0, top: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(S.m, ins.top + S.s, S.m, S.m),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(2, 4, 14, .95), rgba(2, 4, 14, .7), rgba(2, 4, 14, 0)])),
        child: Row(children: [
          Press(
            onPress: onBack,
            child: Container(
              width: 44, height: 44, margin: const EdgeInsets.only(right: S.s), alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(8, 14, 40, .85), border: Border.all(color: C.line)),
              child: T('‹', style: fs(F.title, 26, color: C.text, height: 1)),
            ),
          ),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 44), child: right ?? const SizedBox.shrink()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: S.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (en != null) T(en!, n: 1, style: fs(F.head, 9, ls: 3, color: accent ?? C.cyan)),
                T(title, n: 1, style: fs(F.title, TS.title)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class Skeleton extends StatelessWidget {
  final int rows;
  final double h;
  const Skeleton({super.key, this.rows = 4, this.h = 72});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < rows; i++)
          Container(
            height: h, margin: const EdgeInsets.only(bottom: S.s),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: rgba(60, 90, 180, .18), border: Border.all(color: C.line)),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: .35, end: .7, duration: 900.ms, curve: Curves.easeInOutSine).shimmer(duration: 1400.ms, color: const Color(0x22FFFFFF)),
      ]);
}

class Empty extends StatelessWidget {
  final String? img;
  final String title;
  final String? sub, action;
  final VoidCallback? onAction;
  const Empty({super.key, this.img, required this.title, this.sub, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.xl, horizontal: S.xl),
        child: Column(children: [
          Opacity(opacity: .85, child: Img(img ?? UI2['x_ball'], w: 72, h: 72)),
          Padding(padding: const EdgeInsets.only(top: S.s), child: T(title, align: TextAlign.center, style: fs(F.bold, TS.h))),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: S.xs), child: T(sub!, align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim))),
          if (action != null && onAction != null) Padding(padding: const EdgeInsets.only(top: S.l), child: SizedBox(width: 180, child: Btn(label: action!, small: true, colors: G.dark, onPress: onAction))),
        ]),
      ).animate().fadeIn(duration: 300.ms);
}

class ErrorState extends StatelessWidget {
  final String msg;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.msg, this.onRetry});
  @override
  Widget build(BuildContext context) => Empty(img: UI2['c_bell'], title: 'مشکلی پیش اومد', sub: msg, action: onRetry != null ? 'تلاش دوباره' : null, onAction: onRetry);
}

class Badge2 extends StatelessWidget {
  final String label;
  final Color? color;
  final bool live;
  const Badge2({super.key, required this.label, this.color, this.live = false});
  @override
  Widget build(BuildContext context) {
    final c = color ?? C.cyan;
    return Container(
      height: 22, margin: const EdgeInsets.only(left: S.xs), padding: const EdgeInsets.symmetric(horizontal: S.s),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: c.withValues(alpha: .53)), color: c.withValues(alpha: .13)),
      child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
        if (live)
          Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: c))
              .animate(onPlay: (x) => x.repeat(reverse: true))
              .fade(begin: .4, end: 1, duration: 700.ms),
        T(label, n: 1, style: fs(F.bold, TS.tiny, color: c)),
      ]),
    );
  }
}

class Card2 extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final VoidCallback? onPress;
  const Card2({super.key, required this.child, this.accent, this.onPress});
  @override
  Widget build(BuildContext context) {
    final body = Panel(accent: accent, noAccent: accent == null, pad: const EdgeInsets.all(S.m), child: child);
    return onPress != null ? Press(onPress: onPress, scaleTo: .98, child: body) : body;
  }
}

class Tabs2<K> extends StatelessWidget {
  final List<(K, String)> items;
  final K value;
  final ValueChanged<K> onChange;
  const Tabs2({super.key, required this.items, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => Container(
        height: 44, padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: rgba(6, 10, 30, .8), border: Border.all(color: C.line)),
        child: Row(textDirection: TextDirection.rtl, children: [
          for (final (k, l) in items)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  buzz();
                  onChange(k);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    color: k == value ? rgba(79, 227, 255, .22) : Colors.transparent,
                    border: Border.all(color: k == value ? C.cyan : Colors.transparent),
                  ),
                  child: T(l, n: 1, style: fs(F.bold, TS.small, color: k == value ? Colors.white : C.dim)),
                ),
              ),
            ),
        ]),
      );
}

class StatBars extends StatelessWidget {
  final int power, accuracy;
  final bool compact;
  const StatBars({super.key, required this.power, required this.accuracy, this.compact = false});
  Widget _row(String label, int v, Color c) => Padding(
        padding: EdgeInsets.only(top: compact ? 2 : 4),
        child: Row(textDirection: TextDirection.rtl, children: [
          SizedBox(width: compact ? 26 : 34, child: T(label, align: TextAlign.right, style: fs(F.body, compact ? 9 : TS.tiny, color: C.dim))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(textDirection: TextDirection.rtl, children: [
                for (var i = 0; i < 10; i++)
                  Expanded(child: Container(height: compact ? 4 : 6, margin: const EdgeInsets.only(left: 1.5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < v ? c : const Color(0x1AFFFFFF)))),
              ]),
            ),
          ),
          if (!compact) SizedBox(width: 20, child: T(faNum(v), style: fs(F.bold, TS.tiny, color: c))),
        ]),
      );
  @override
  Widget build(BuildContext context) => Column(children: [_row('قدرت', power, C.orange), _row('دقت', accuracy, C.cyan)]);
}

// ---------- extra shared pieces (Spinner, input field, leagues, small helpers) ----------
class Spinner extends StatelessWidget {
  final double size;
  final Color? color;
  const Spinner({super.key, this.size = 28, this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size > 30 ? 36 : 22, height: size > 30 ? 36 : 22, child: CircularProgressIndicator(strokeWidth: size > 30 ? 3.5 : 2.5, color: color ?? C.cyan));
}

/// text input (RN online/ui Field): RTL, rounded glass, optional label + error
class OField extends StatefulWidget {
  final String? label, placeholder, error, initial;
  final TextEditingController? ctl;
  final ValueChanged<String>? onChanged, onSubmit;
  final int? maxLength;
  final int lines;
  final bool center, ltr, mono, upper;
  final TextInputType? keyboard;
  const OField({super.key, this.label, this.placeholder, this.error, this.initial, this.ctl, this.onChanged, this.onSubmit, this.maxLength, this.lines = 1, this.center = false, this.ltr = false, this.mono = false, this.upper = false, this.keyboard});
  @override
  State<OField> createState() => _OFieldState();
}

class _OFieldState extends State<OField> {
  late final TextEditingController c = widget.ctl ?? TextEditingController(text: widget.initial ?? '');
  @override
  void dispose() {
    if (widget.ctl == null) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.label != null) Padding(padding: const EdgeInsets.only(bottom: S.xs), child: T(widget.label!, align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim))),
          TextField(
            controller: c,
            maxLength: widget.maxLength,
            minLines: widget.lines,
            maxLines: widget.lines == 1 ? 1 : widget.lines + 2,
            keyboardType: widget.keyboard ?? (widget.lines > 1 ? TextInputType.multiline : null),
            textCapitalization: widget.upper ? TextCapitalization.characters : TextCapitalization.none,
            autocorrect: false,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmit,
            textDirection: widget.ltr || widget.mono ? TextDirection.ltr : TextDirection.rtl,
            textAlign: widget.center ? TextAlign.center : TextAlign.right,
            style: widget.mono ? fs(F.head, 15, ls: 3) : fs(F.fa, 15),
            cursorColor: C.cyan,
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              hintText: widget.placeholder == null ? null : tr(widget.placeholder!),
              hintStyle: fs(F.fa, 14, color: C.dim2),
              filled: true,
              fillColor: rgba(6, 10, 30, .85),
              contentPadding: const EdgeInsets.symmetric(horizontal: S.m, vertical: 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: widget.error != null ? C.red : C.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.cyan)),
            ),
          ),
          if (widget.error != null) Padding(padding: const EdgeInsets.only(top: S.xs), child: T(widget.error!, align: TextAlign.right, style: fs(F.body, TS.cap, color: C.red))),
        ]),
      );
}

const Map<String, String> LEAGUE_IMG = {'bronze': 'medal_bronze', 'silver': 'medal_silver', 'gold': 'medal_gold', 'platinum': 'medal_epic', 'diamond': 'shield_epic', 'master': 'shield_star', 'legend': 'shield_crown'};
String? leagueImg(String? id) => UI[LEAGUE_IMG[id] ?? 'medal_bronze'];

/// leagues table, fetched once per session
class Leagues {
  static List<JRow>? cache;
  static Future<List<JRow>>? _f;
  static Future<List<JRow>> load() => cache != null
      ? Future.value(cache)
      : (_f ??= supabase.from('leagues').select().order('sort').then((d) => cache = List<JRow>.from(d)).whenComplete(() => _f = null));
}

/// rebuilds when the leagues arrive
class LeaguesBuilder extends StatelessWidget {
  final Widget Function(BuildContext, List<JRow>?) builder;
  const LeaguesBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => Leagues.cache != null
      ? builder(context, Leagues.cache)
      : FutureBuilder<List<JRow>>(future: Leagues.load().catchError((_) => <JRow>[]), builder: (c, s) => builder(c, s.data));
}

Color colorOf(Object? s, [Color? d]) {
  if (s is String && s.startsWith('#')) return hex(s);
  return d ?? C.cyan;
}

/// RN Row (row-reverse) helper
Widget rrow(List<Widget> children, {CrossAxisAlignment cross = CrossAxisAlignment.center, MainAxisAlignment main = MainAxisAlignment.start}) =>
    Row(textDirection: TextDirection.rtl, crossAxisAlignment: cross, mainAxisAlignment: main, children: children);

/// RN alignItems:'flex-end' column
Widget rcol(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: children);

/// a tiny ticker for countdowns
mixin Ticking<W extends StatefulWidget> on State<W> {
  Timer? _tick;
  void startTicking(Duration d) => _tick = Timer.periodic(d, (_) {
        if (mounted) setState(() {});
      });
  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
