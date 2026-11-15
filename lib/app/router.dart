import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/profile/profile_service.dart';
import '../core/settings/app_settings.dart';
import '../core/storage/local_store.dart';
import '../worlds/arcade/arcade_page.dart';
import '../worlds/arcade/game_setup_page.dart';
import '../worlds/arcade/online/leaderboard_page.dart';
import '../worlds/arcade/online/online_lobby_page.dart';
import '../worlds/hub/hub_page.dart';
import '../worlds/journey/journey_page.dart';
import '../worlds/nexora_exchange/exchange_page.dart';
import '../worlds/nova_gallery/nova_gallery_page.dart';
import '../worlds/onboarding/onboarding_page.dart';
import '../worlds/oracle_core/oracle_core_page.dart';
import '../worlds/orbit_network/orbit_network_page.dart';
import '../worlds/personal_orbit/personal_orbit_page.dart';
import '../worlds/settings/account_page.dart';
import '../worlds/settings/settings_page.dart';
import '../worlds/social_station/social_station_page.dart';

GoRouter buildRouter(WidgetRef ref) {
  final settings = ref.read(settingsProvider);
  final profile = ref.read(profileProvider);
  final String initial;
  if (!settings.journeySeen) {
    initial = '/journey';
  } else if (!profile.hasIdentity) {
    initial = '/onboarding';
  } else {
    initial = '/hub';
  }

  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/journey',
        pageBuilder: (context, state) => _fade(
          state,
          JourneyPage(short: state.uri.queryParameters['mode'] == 'short'),
        ),
      ),
      GoRoute(path: '/onboarding', pageBuilder: (context, state) => _fade(state, const OnboardingPage())),
      GoRoute(path: '/hub', pageBuilder: (context, state) => _fade(state, const HubPage())),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
      GoRoute(
        path: '/oracle',
        pageBuilder: (context, state) => _warp(
          state,
          _WorldVisit(id: 'oracle_core', child: OracleCorePage(initialQuery: state.uri.queryParameters['q'])),
        ),
      ),
      GoRoute(
        path: '/world/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _warp(state, _WorldVisit(id: id, child: _worldPage(id)));
        },
      ),
      GoRoute(
        path: '/online/:gameId',
        builder: (context, state) => OnlineLobbyPage(
          gameId: state.pathParameters['gameId'] ?? '',
          joinCode: state.uri.queryParameters['code'],
        ),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (context, state) => LeaderboardPage(initialGame: state.uri.queryParameters['game']),
      ),
      GoRoute(
        path: '/arcade/:gameId',
        builder: (context, state) => GameSetupPage(gameId: state.pathParameters['gameId'] ?? ''),
      ),
    ],
    errorBuilder: (context, state) => const HubPage(),
  );
}

Widget _worldPage(String id) {
  switch (id) {
    case 'nova_gallery':
      return const NovaGalleryPage();
    case 'orbit_network':
      return const OrbitNetworkPage();
    case 'nexora_arcade':
      return const ArcadePage();
    case 'oracle_core':
      return const OracleCorePage();
    case 'personal_orbit':
      return const PersonalOrbitPage();
    case 'social_station':
      return const SocialStationPage();
    case 'nexora_exchange':
      return const ExchangePage();
    default:
      return const HubPage();
  }
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 450),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

/// Cinematic "warp" transition into a world (zoom + fade). Reduced motion → plain fade.
CustomTransitionPage<void> _warp(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        if (MediaQuery.of(context).disableAnimations) {
          return FadeTransition(opacity: curved, child: child);
        }
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 1.18, end: 1.0).animate(curved), child: child),
        );
      },
    );

/// Records the first visit to each world (for the World Traveler achievement).
class _WorldVisit extends ConsumerStatefulWidget {
  const _WorldVisit({required this.id, required this.child});
  final String id;
  final Widget child;

  @override
  ConsumerState<_WorldVisit> createState() => _WorldVisitState();
}

class _WorldVisitState extends ConsumerState<_WorldVisit> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = LocalStore.instance;
      final visited = (store.getJsonList('hub.visited') ?? const []).map((e) => '$e').toSet();
      if (visited.add(widget.id)) {
        store.setJson('hub.visited', visited.toList());
        final p = ref.read(profileProvider);
        p.bump('worlds.visited');
        p.award('world.first_visit.${widget.id}', xp: 20, coins: 10);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
