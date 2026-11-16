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

/// NEXORA ARCADE lobby (STEP_18): game pedestals, records, quick play.
class ArcadePage extends ConsumerWidget {
  const ArcadePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return DefaultTabController(
      length: 2,
      child: NxWorldScaffold(
        title: 'NEXORA ARCADE',
        palette: WorldPalette.arcade,
        body: Column(children: [
          TabBar(
            indicatorColor: WorldPalette.arcade.primary,
            labelColor: WorldPalette.arcade.primary,
            unselectedLabelColor: NxColors.textDim,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: context.tx('بازی‌ها', 'Games')),
              Tab(text: context.tx('رکوردها', 'Records')),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _GamesGrid(profile: p),
              _Records(profile: p),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GamesGrid extends StatelessWidget {
  const _GamesGrid({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.md, NxSpace.md, 0),
          child: GlassPanel(
            borderColor: WorldPalette.arcade.primary.withValues(alpha: 0.6),
            child: Row(children: [
              const OracleAvatar(pose: 'cheer', size: 70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tx('${profile.totalGamesPlayed} بازی · ${profile.totalWins} برد',
                      '${profile.totalGamesPlayed} played · ${profile.totalWins} wins'),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    context.tx('همه‌ی بازی‌ها آفلاین با بات هوشمند یا دو نفره روی یک گوشی کار می‌کنند.',
                        'Every game works offline against smart bots or with friends on one phone.'),
                    style: const TextStyle(color: NxColors.textDim, fontSize: 12),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(NxSpace.md),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _GameTile(game: kGames[i], stats: profile.stats[kGames[i].id]),
            childCount: kGames.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.sm),
          child: GlassPanel(
            onTap: () => context.push('/tournaments'),
            borderColor: NxColors.gold.withValues(alpha: 0.7),
            tint: NxColors.gold.withValues(alpha: 0.08),
            child: Row(children: [
              const Icon(Icons.emoji_events_rounded, color: NxColors.gold, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tx('تورنمنت‌های آنلاین', 'Online tournaments'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(context.tx('حذفی، لیگ، گروهی و سوئیسی با جایزه', 'Knockout, league, groups and swiss with prizes'),
                      style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
          child: GlassPanel(
            onTap: () => context.push('/world/social_station'),
            child: Row(children: [
              const Icon(Icons.emoji_events_rounded, color: NxColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.tx('مسابقه و لیگ با دوستان در ایستگاه اجتماعی', 'Tournaments & leagues with friends in Social Station')),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game, required this.stats});
  final GameInfo game;
  final GameStats? stats;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      borderColor: game.accent.withValues(alpha: 0.55),
      tint: game.accent.withValues(alpha: 0.08),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/arcade/${game.id}');
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Hero(
            tag: 'pedestal_${game.id}',
            child: Image.asset(AppAssets.pedestal(game.id), cacheWidth: 360, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.sports_esports, size: 60, color: game.accent)),
          ),
        ),
        const SizedBox(height: 6),
        Text(context.tx(game.nameFa, game.nameEn),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, color: game.accent)),
        Text(context.tx(game.taglineFa, game.taglineEn),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.people_alt_rounded, size: 13, color: NxColors.textDim.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(game.minPlayers == game.maxPlayers ? '${game.minPlayers}' : '${game.minPlayers}-${game.maxPlayers}',
              style: const TextStyle(fontSize: 11, color: NxColors.textDim)),
          const Spacer(),
          if (stats != null)
            Text('${stats!.won}/${stats!.played}', style: const TextStyle(fontSize: 11, color: NxColors.gold)),
        ]),
      ]),
    );
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: [
        FilledButton.icon(
          onPressed: () => context.push('/leaderboard'),
          icon: const Icon(Icons.leaderboard_rounded),
          label: Text(context.tx('رتبه‌بندی جهانی (بازی‌های آنلاین)', 'Global rankings (online games)')),
        ),
        const SizedBox(height: NxSpace.md),
        for (final g in kGames)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              child: Row(children: [
                Image.asset(AppAssets.pedestal(g.id), width: 46, cacheWidth: 140),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tx(g.nameFa, g.nameEn), style: TextStyle(fontWeight: FontWeight.w800, color: g.accent)),
                    Builder(builder: (context) {
                      final s = profile.stats[g.id];
                      if (s == null) {
                        return Text(context.tx('هنوز بازی نکرده‌ای', 'Not played yet'),
                            style: const TextStyle(color: NxColors.textDim, fontSize: 12));
                      }
                      final rate = s.played == 0 ? 0 : (s.won * 100 / s.played).round();
                      return Text(
                        context.tx('بازی ${s.played} · برد ${s.won} · باخت ${s.lost} · مساوی ${s.draw} · ٪$rate',
                            'Played ${s.played} · W ${s.won} · L ${s.lost} · D ${s.draw} · $rate%'),
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12),
                      );
                    }),
                  ]),
                ),
                if ((profile.stats[g.id]?.best ?? 0) > 0)
                  NxPill(label: '${context.tx('بهترین', 'Best')} ${profile.stats[g.id]!.best}', color: NxColors.gold),
              ]),
            ),
          ),
      ],
    );
  }
}
