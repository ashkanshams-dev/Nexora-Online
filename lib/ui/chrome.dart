// App chrome — port of src/ui/Chrome.tsx: bottom tab bar (sliding highlight), top HUD, bottom sheet, modal card.
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/util.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../store.dart';
import 'kit.dart';
import 'menu_assets.dart';
import 'theme.dart';

enum Tab { home, social, play, shop, profile }

final _TABS = [
  (Tab.home, 'خانه', MENU.ic_home),
  (Tab.play, 'بازی', MENU.ic_play),
  (Tab.social, 'اجتماعی', MENU.ic_friends),
  (Tab.shop, 'فروشگاه', MENU.ic_shop),
  (Tab.profile, 'پروفایل', MENU.ic_trophy),
];

const double TAB_H = 74;

/// avatar art for a disc id or an uploaded avatar url
String? discImg(String? id) {
  if (id == null || id.isEmpty) return teamImg('club00');
  final t = teamById(id);
  return teamImg(teamKey(t));
}

class TabBar2 extends StatelessWidget {
  final Tab tab;
  final ValueChanged<Tab> onTab;
  final Set<Tab> badge;
  const TabBar2({super.key, required this.tab, required this.onTab, this.badge = const {}});
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final W = MediaQuery.sizeOf(context).width;
    final barW = math.min(W - 20, 520.0), cw = barW / _TABS.length;
    final idx = _TABS.indexWhere((t) => t.$1 == tab);
    return Padding(
      padding: EdgeInsets.only(bottom: math.max(10, ins.bottom)),
      child: Center(
        heightFactor: 1,
        child: Container(
          width: barW,
          height: TAB_H - 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: rgba(92, 225, 255, .28)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(22, 34, 86, .96), rgba(8, 12, 36, .98)]),
            boxShadow: [BoxShadow(color: hex('#4c6bff').withValues(alpha: .5), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Stack(children: [
            Positioned(top: 0, left: 40, right: 40, child: Container(height: 1, color: rgba(160, 230, 255, .45))),
            TweenAnimationBuilder<double>(
              tween: Tween(end: idx.toDouble()),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (_, x, _) => Positioned(
                top: 5, bottom: 5, right: 6 + x * cw, width: cw - 12,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: rgba(79, 227, 255, .45)),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(79, 227, 255, .28), rgba(109, 91, 255, .10)]),
                  ),
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Container(width: 18, height: 3, decoration: BoxDecoration(color: C.cyan, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: C.cyan, blurRadius: 6)])),
                ),
              ),
            ),
            Row(textDirection: TextDirection.rtl, children: [
              for (var i = 0; i < _TABS.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i != idx) {
                        sfx(Sfx.ui);
                        buzz();
                      }
                      onTab(_TABS[i].$1);
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: i == idx ? 1 : 0),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      builder: (_, sc, _) => Stack(alignment: Alignment.center, children: [
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Opacity(opacity: (.62 + sc * .38).clamp(0, 1), child: Transform.translate(offset: Offset(0, -sc * 2), child: Img(_TABS[i].$3, w: 30, h: 30))),
                          Opacity(opacity: (.55 + sc * .45).clamp(0, 1), child: T(_TABS[i].$2, style: fs(F.bold, 10, color: i == idx ? C.cyan : C.dim))),
                        ]),
                        if (badge.contains(_TABS[i].$1))
                          Positioned(top: 8, right: cw * .28, child: Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: C.red, border: Border.all(color: hex('#0b1236'), width: 1.5)))),
                      ]),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class Hud extends StatelessWidget {
  final VoidCallback onProfile, onSettings, onDaily, onShop;
  final bool dailyReady;
  const Hud({super.key, required this.onProfile, required this.onSettings, required this.onDaily, required this.dailyReady, required this.onShop});
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([Store.I, Auth.I]),
      builder: (context, _) {
        final p = Store.I.p, prof = Auth.I.profile;
        final lp = prof != null ? levelProgress(ri(prof, 'xp')) : null;
        final local = level(p.xp);
        final lvl = lp?.level ?? local.level, cur = lp?.cur ?? local.cur, need = lp?.need ?? local.need;
        final name = prof?['username'] as String? ?? p.name;
        final avUrl = prof?['avatar_url'] as String?;
        final avatar = prof != null ? (avUrl ?? discImg(prof['equipped_disc'] as String?)) : teamImg(teamKey(teamById(p.team)));
        return Container(
          padding: EdgeInsets.fromLTRB(10, ins.top + 6, 10, 14),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(2, 4, 14, .92), rgba(2, 4, 14, .55), rgba(2, 4, 14, 0)])),
          child: Row(children: [
            Press(
              onPress: onProfile,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 3, 3, 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), border: Border.all(color: rgba(92, 225, 255, .35)), color: rgba(8, 14, 40, .8)),
                child: Row(children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        T(name, n: 1, style: fs(F.bold, 13)),
                        Container(
                          width: 70, height: 5, margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: const Color(0x1FFFFFFF)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(widthFactor: math.max(.04, cur / math.max(1, need)).clamp(0, 1), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: C.cyan))),
                        ),
                      ]),
                    ),
                  ),
                  Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                    Container(
                      width: 42, height: 42, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 2), color: hex('#050816')),
                      child: ClipOval(child: Img(avatar, w: 36, h: 36, fit: avUrl != null ? BoxFit.cover : BoxFit.contain)),
                    ),
                    Positioned(
                      bottom: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 20), height: 16, padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: C.gold),
                        alignment: Alignment.center,
                        child: Text('$lvl', style: fs(F.title, 9, color: hex('#04122a'))),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            const Spacer(),
            Pill(icon: MENU.g_gem, v: prof != null ? ri(prof, 'gems') : p.gems, onPress: onShop),
            Pill(icon: MENU.g_coin, v: p.coins, tint: C.gold, onPress: onShop, plus: true),
            _GiftBtn(ready: dailyReady, onPress: onDaily),
            IconButton2(MENU.ic_settings, onPress: onSettings),
          ]),
        );
      },
    );
  }
}

class _GiftBtn extends StatelessWidget {
  final bool ready;
  final VoidCallback onPress;
  const _GiftBtn({required this.ready, required this.onPress});
  @override
  Widget build(BuildContext context) {
    Widget gift = Img(MENU.ic_gift, w: 40, h: 40);
    if (ready) {
      gift = gift
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .custom(duration: 900.ms, curve: Curves.easeInOutSine, builder: (_, w, c) => Transform.rotate(angle: (w - .5) * 16 * math.pi / 180, child: Transform.scale(scale: 1 + w * .08, child: c)));
    }
    return Press(
      onPress: onPress,
      scaleTo: .88,
      child: SizedBox(
        width: 44, height: 44,
        child: Stack(alignment: Alignment.center, children: [
          gift,
          if (ready) Positioned(top: 3, right: 3, child: Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: C.red, border: Border.all(color: hex('#0b1236'), width: 1.5)))),
        ]),
      ),
    );
  }
}

/// bottom sheet: spring in, drag the handle down to dismiss, back closes
Future<R?> showNxSheet<R>(BuildContext context, {required WidgetBuilder builder, String? title, String? en, double height = .84, Color? accent}) {
  final a = accent ?? C.cyan;
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: rgba(1, 3, 12, .72),
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 420), reverseDuration: Duration(milliseconds: 240), curve: Curves.easeOutBack),
    builder: (ctx) {
      final H = MediaQuery.sizeOf(ctx).height, ins = MediaQuery.paddingOf(ctx);
      final h = math.min(H * height, H - ins.top - 20);
      return Container(
        height: h,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: a.withValues(alpha: .33)),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [hex('#18245a'), hex('#0b1236'), hex('#060a22')]),
          boxShadow: [BoxShadow(color: a.withValues(alpha: .5), blurRadius: 30, offset: const Offset(0, -4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(child: Opacity(opacity: .5, child: Image.asset(UI['scan']!, fit: BoxFit.cover))),
          Column(children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Column(children: [
                Container(width: 46, height: 5, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: a.withValues(alpha: .8))),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(children: [
                      IconButton2(MENU.g_x, onPress: () => Navigator.of(ctx).pop()),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (en != null) T(en, style: fs(F.head, 9, ls: 3, color: a)),
                          T(title, n: 1, style: fs(F.title, 20)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ),
            Expanded(child: Padding(padding: EdgeInsets.only(bottom: ins.bottom), child: builder(ctx))),
          ]),
        ]),
      );
    },
  );
}

/// full-screen modal card (daily reward, chest, quick profile)
Future<R?> showNxModal<R>(BuildContext context, {required WidgetBuilder builder, Color? accent}) {
  final a = accent ?? C.gold;
  return showGeneralDialog<R>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: rgba(1, 3, 12, .8),
    transitionDuration: const Duration(milliseconds: 380),
    transitionBuilder: (_, an, _, child) => FadeTransition(opacity: an, child: ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(CurvedAnimation(parent: an, curve: Curves.elasticOut, reverseCurve: Curves.easeIn)), child: child)),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: math.min(MediaQuery.sizeOf(ctx).width * .88, 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: a.withValues(alpha: .53)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [hex('#1d2a66'), hex('#0c1238'), hex('#070a22')]),
            boxShadow: [BoxShadow(color: a.withValues(alpha: .6), blurRadius: 30)],
          ),
          clipBehavior: Clip.antiAlias,
          child: builder(ctx),
        ),
      ),
    ),
  );
}

/// toast (top, spring in, auto-hide after 1.7 s)
OverlayEntry? _toastE;
void showToast(BuildContext context, String m, [String k = 'info']) {
  _toastE?.remove();
  final ov = Overlay.maybeOf(context, rootOverlay: true);
  if (ov == null) return;
  final top = MediaQuery.paddingOf(context).top + 64;
  final col = k == 'err' ? C.red : k == 'ok' ? C.green : C.cyan;
  final icon = k == 'err' ? UI2['c_bell'] : k == 'ok' ? UI2['x_star'] : UI2['c_mega'];
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => Positioned(
      top: top, left: 0, right: 0,
      child: IgnorePointer(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .9),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: rgba(10, 16, 44, .96), border: Border.all(color: col), boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 10)]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.only(right: 6), child: Img(icon, w: 26, h: 26)),
                Flexible(child: T(m, style: fs(F.bold, 14))),
              ]),
            ),
          )
              .animate(onComplete: (_) {
                if (_toastE == e) {
                  e.remove();
                  _toastE = null;
                }
              })
              .slideY(begin: -.6, end: 0, duration: 380.ms, curve: Curves.easeOutBack)
              .fadeIn(duration: 200.ms)
              .then(delay: 1700.ms)
              .fadeOut(duration: 250.ms),
        ),
      ),
    ),
  );
  _toastE = e;
  ov.insert(e);
}
