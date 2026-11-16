import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/game_registry.dart';
import '../world_registry.dart';
import 'hub_search.dart';

/// NEXORA HUB — the station at the center of the universe (STEP_11).
/// 2.5D orbital ring of world portals: drag to rotate, tap to warp in.
/// Quick menu keeps every important feature ≤ 2 taps away.
class HubPage extends ConsumerStatefulWidget {
  const HubPage({super.key});

  @override
  ConsumerState<HubPage> createState() => _HubPageState();
}

class _HubPageState extends ConsumerState<HubPage> with TickerProviderStateMixin {
  double _angle = 0; // ring rotation (radians)
  double _velocity = 0;
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final AnimationController _inertia = AnimationController.unbounded(vsync: this)..addListener(_tick);
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _idle.dispose();
    _inertia.dispose();
    super.dispose();
  }

  void _tick() {
    final now = _inertia.lastElapsedDuration ?? Duration.zero;
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    setState(() {
      _angle += _velocity * dt;
      _velocity *= pow(0.04, dt).toDouble();
      if (_velocity.abs() < 0.02) {
        _velocity = 0;
        _inertia.stop();
        _snap();
      }
    });
  }

  void _snap() {
    final step = 2 * pi / kWorlds.length;
    final target = (_angle / step).round() * step;
    setState(() => _angle = target);
  }

  int get _frontIndex {
    final step = 2 * pi / kWorlds.length;
    final n = kWorlds.length;
    final idx = (-_angle / step).round() % n;
    return (idx + n) % n;
  }

  void _openWorld(NexoraWorld w) {
    HapticFeedback.selectionClick();
    context.push('/world/${w.id}');
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final s = ref.watch(settingsProvider);
    final front = kWorlds[_frontIndex];
    return Scaffold(
      body: NxBackground(
        palette: WorldPalette.hub,
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(profile: p),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  radius: 40,
                  onTap: () => showSearch<void>(context: context, delegate: HubSearchDelegate(isFa: context.isFa)),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, color: NxColors.textDim),
                    const SizedBox(width: 8),
                    Text(context.tx('جستجو در دنیاها، بازی‌ها و قابلیت‌ها', 'Search worlds, games & features'),
                        style: const TextStyle(color: NxColors.textDim)),
                  ]),
                ),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, c) => _ring(c, s)),
              ),
              _FrontWorldCard(world: front, onEnter: () => _openWorld(front)),
              const SizedBox(height: NxSpace.sm),
              _QuickRow(profile: p),
              const SizedBox(height: NxSpace.sm),
            ],
          ),
        ),
      ),
      floatingActionButton: _OracleOrbButton(onTap: () => context.push('/oracle')),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
    );
  }

  Widget _ring(BoxConstraints c, AppSettings s) {
    final w = c.maxWidth;
    final h = c.maxHeight;
    final cx = w / 2;
    final cy = h * 0.55;
    final rx = w * 0.40;
    final ry = h * 0.17;
    final n = kWorlds.length;
    final step = 2 * pi / n;

    final items = <({double depth, Widget widget})>[];
    for (var i = 0; i < n; i++) {
      final a = _angle + i * step;
      final x = cx + rx * sin(a);
      final depth = cos(a); // 1 front, -1 back
      final y = cy + ry * depth;
      final scale = 0.55 + 0.45 * ((depth + 1) / 2);
      final size = min(w, h) * 0.34 * scale;
      final opacity = (0.35 + 0.65 * ((depth + 1) / 2)).clamp(0.0, 1.0);
      final world = kWorlds[i];
      items.add((
        depth: depth,
        widget: Positioned(
          left: x - size / 2,
          top: y - size * 0.85,
          width: size,
          height: size,
          child: Opacity(
            opacity: opacity,
            child: GestureDetector(
              onTap: () => _openWorld(world),
              child: _Portal(world: world, glow: depth > 0.9 && s.fancyEffects, idle: _idle, reduced: s.reducedMotion),
            ),
          ),
        ),
      ));
    }
    items.sort((a, b) => a.depth.compareTo(b.depth));

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _inertia.stop(),
      onHorizontalDragUpdate: (d) => setState(() => _angle += d.delta.dx / (rx * 1.2)),
      onHorizontalDragEnd: (d) {
        _velocity = d.velocity.pixelsPerSecond.dx / (rx * 1.2);
        if (s.reducedMotion || _velocity.abs() < 0.1) {
          _velocity = 0;
          _snap();
          return;
        }
        _last = Duration.zero;
        _inertia.repeat(min: 0, max: 1, period: const Duration(seconds: 1));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // central command platform + station core
          Positioned(
            left: cx - w * 0.42,
            top: cy - h * 0.12,
            width: w * 0.84,
            child: Opacity(
              opacity: 0.9,
              child: Image.asset(AppAssets.worldsHubPropsCommandPlatformOctagon,
                  cacheWidth: (w * 2).round(), fit: BoxFit.contain),
            ),
          ),
          Positioned(
            left: cx - 70,
            top: cy - h * 0.36,
            width: 140,
            child: AnimatedBuilder(
              animation: _idle,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, s.reducedMotion ? 0 : sin(_idle.value * 2 * pi) * 6),
                child: child,
              ),
              child: Image.asset(AppAssets.worldsHubPropsSetEnergyCore, cacheWidth: 360, fit: BoxFit.contain),
            ),
          ),
          for (final it in items) it.widget,
        ],
      ),
    );
  }
}

class _Portal extends StatelessWidget {
  const _Portal({required this.world, required this.glow, required this.idle, required this.reduced});
  final NexoraWorld world;
  final bool glow;
  final Animation<double> idle;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(AppAssets.portal(world.id), cacheWidth: 420, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(world.icon, size: 64, color: world.palette.primary));
    return Stack(alignment: Alignment.center, children: [
      if (glow)
        AnimatedBuilder(
          animation: idle,
          builder: (_, __) {
            final t = reduced ? 0.5 : (sin(idle.value * 2 * pi) + 1) / 2;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: world.palette.primary.withValues(alpha: 0.25 + 0.25 * t),
                      blurRadius: 40 + 20 * t,
                      spreadRadius: 4),
                ],
              ),
            );
          },
        ),
      img,
    ]);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.sm),
      child: Row(children: [
        GestureDetector(
          onTap: () => context.push('/world/personal_orbit'),
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [NxColors.turquoise, NxColors.violet]),
              boxShadow: [BoxShadow(color: NxColors.electricBlue.withValues(alpha: 0.4), blurRadius: 12)],
            ),
            child: ClipOval(
              child: Container(
                color: NxColors.navy,
                child: Image.asset('assets/characters/oracle/emotes/${profile.avatarCore}.webp',
                    cacheWidth: 140, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.person, color: NxColors.iceWhite)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(profile.username.isEmpty ? 'Explorer' : profile.username,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text('${context.tx(profile.rankTitleFa, profile.rankTitleEn)} · ${profile.explorerId}',
                style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
          ]),
        ),
        const WalletChip(),
        const SizedBox(width: 56), // space for ORACLE orb (endTop FAB)
      ]),
    );
  }
}

class _FrontWorldCard extends StatelessWidget {
  const _FrontWorldCard({required this.world, required this.onEnter});
  final NexoraWorld world;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
      child: AnimatedSwitcher(
        duration: NxMotion.normal,
        child: GlassPanel(
          key: ValueKey(world.id),
          borderColor: world.palette.primary.withValues(alpha: 0.6),
          child: Row(children: [
            Icon(world.icon, color: world.palette.primary, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.isFa ? world.nameFa : world.name,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: world.palette.primary)),
                Text(context.tx(world.taglineFa, world.taglineEn),
                    style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
              ]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: world.palette.primary),
              onPressed: onEnter,
              child: Text(context.tx('ورود', 'Enter')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QuickRow extends ConsumerWidget {
  const _QuickRow({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <({IconData icon, String fa, String en, VoidCallback onTap, bool badge})>[
      (icon: Icons.sports_esports_rounded, fa: 'آرکید', en: 'Arcade', onTap: () => context.push('/world/nexora_arcade'), badge: false),
      (icon: Icons.emoji_events_rounded, fa: 'تورنمنت', en: 'Cups', onTap: () => context.push('/tournaments'), badge: false),
      (icon: Icons.forum_rounded, fa: 'پیام', en: 'Chat', onTap: () => context.push('/world/orbit_network'), badge: false),
      (
        icon: Icons.card_giftcard_rounded,
        fa: 'جایزه',
        en: 'Reward',
        onTap: () async {
          final o = ref.read(profileProvider).claimDaily();
          if (o == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(context.tx('جایزه‌ی امروز را گرفته‌ای. فردا برگرد!', 'Already claimed today. Come back tomorrow!'))));
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(context.tx('+${o.coins} سکه و +${o.xp} XP', '+${o.coins} coins and +${o.xp} XP'))));
          await showAwardOutcome(context, o);
        },
        badge: profile.canClaimDaily
      ),
      (icon: Icons.storefront_rounded, fa: 'بازار', en: 'Shop', onTap: () => context.push('/world/nexora_exchange'), badge: false),
      (icon: Icons.menu_rounded, fa: 'منو', en: 'Menu', onTap: () => _showMenu(context), badge: false),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final it in items)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: it.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Badge(isLabelVisible: it.badge, smallSize: 9, child: Icon(it.icon, color: NxColors.iceWhite)),
                    const SizedBox(height: 3),
                    Text(context.tx(it.fa, it.en), style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const XpBar(),
            const SizedBox(height: NxSpace.md),
            for (final w in kWorlds)
              ListTile(
                leading: Icon(w.icon, color: w.palette.primary),
                title: Text(ctx.isFa ? w.nameFa : w.name),
                subtitle: Text(ctx.tx(w.taglineFa, w.taglineEn), style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/world/${w.id}');
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: Text(ctx.tx('تنظیمات', 'Settings')),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_filter_rounded),
              title: Text(ctx.tx('تماشای دوباره‌ی سفر', 'Replay the journey')),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/journey');
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(ctx.tx('${kGames.length} بازی · ${kWorlds.length} دنیا · نسخه‌ی آفلاین ۱.۰',
                  '${kGames.length} games · ${kWorlds.length} worlds · offline v1.0')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OracleOrbButton extends ConsumerStatefulWidget {
  const _OracleOrbButton({required this.onTap});
  final VoidCallback onTap;

  @override
  ConsumerState<_OracleOrbButton> createState() => _OracleOrbButtonState();
}

class _OracleOrbButtonState extends ConsumerState<_OracleOrbButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(settingsProvider).reducedMotion;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = reduced ? 0.0 : _c.value;
            return Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  transform: GradientRotation(t * 2 * pi),
                  colors: const [NxColors.violet, NxColors.turquoise, NxColors.electricBlue, NxColors.violet],
                ),
                boxShadow: [BoxShadow(color: NxColors.violet.withValues(alpha: 0.6), blurRadius: 18)],
              ),
              padding: const EdgeInsets.all(3),
              child: child,
            );
          },
          child: ClipOval(
            child: Container(
              color: NxColors.navyDeep,
              child: Image.asset(AppAssets.charactersOraclePosesIdle, cacheHeight: 160, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
