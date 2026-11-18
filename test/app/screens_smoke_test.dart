// Smoke tests: the main menu, every reported game screen, the chat screens and the sign-in screens build and run a
// few seconds of frames without exceptions, in English and Persian (RTL). Also drives the real app router as a
// guest: the dock / menu destinations must open a page (or the explicit sign-in screen), never bounce to /hub.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/app/app.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/ui2/nx2_widgets.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:nexora/worlds/arcade/arcade_page.dart';
import 'package:nexora/worlds/arcade/game_host_page.dart';
import 'package:nexora/worlds/arcade/game_setup_page.dart';
import 'package:nexora/worlds/arcade/online/online_lobby_page.dart';
import 'package:nexora/worlds/auth/auth_page.dart';
import 'package:nexora/worlds/auth/signin_required_page.dart';
import 'package:nexora/worlds/hub/hub_page.dart';
import 'package:nexora/worlds/orbit_network/orbit_network_page.dart';
import 'package:nexora/worlds/rooms/rooms_page.dart';
import 'package:nexora/worlds/social_hub/social_hub_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Collects framework errors. Text overflow is ignored: the test font (Ahem) is much wider than the app fonts.
final List<void Function()> _restore = <void Function()>[];

/// Puts the test framework's error handler back (must happen before any expect, or a failure is masked).
void _release() {
  for (final void Function() f in _restore) {
    f();
  }
  _restore.clear();
}

List<String> _captureErrors() {
  final List<String> errs = <String>[];
  final void Function(FlutterErrorDetails)? old = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    final String s = d.exceptionAsString();
    if (s.contains('overflowed by')) return;
    errs.add(s.split('\n').take(3).join(' / '));
  };
  _restore.add(() => FlutterError.onError = old);
  addTearDown(_release);
  return errs;
}

Future<void> _frames(WidgetTester tester, int n, {int ms = 100}) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
}

Widget _host(GameInfo g) =>
    GameHostPage(game: g, mode: GameMode.vsBot, difficulty: BotDifficulty.normal, players: g.defaultPlayers);

void main() {
  const List<String> reportedGames = <String>['finger_soccer', 'pool8', 'mini_golf', 'basketball_battle', 'spy_mafia'];

  final Map<String, (Widget Function(), Type)> screens = <String, (Widget Function(), Type)>{
    'main menu (hub)': (() => const HubPage(), HubPage),
    'arcade (PLAY)': (() => const ArcadePage(), ArcadePage),
    'rooms (dock GAME)': (() => const RoomsPage(), RoomsPage),
    'chat + media hub, messages tab': (() => const SocialHubPage(initial: 1), OrbitNetworkPage),
    'chat (orbit network)': (() => const OrbitNetworkPage(), OrbitNetworkPage),
    'sign-in': (() => const AuthPage(), AuthPage),
    'sign-in required': (() => const SignInRequiredPage(from: '/social'), SignInRequiredPage),
    for (final String id in reportedGames) ...<String, (Widget Function(), Type)>{
      'game setup $id': (() => GameSetupPage(gameId: id), GameSetupPage),
      'game $id vs bot': (() => _host(gameById(id)!), GameHostPage),
    },
  };

  for (final String lang in <String>['en', 'fa']) {
    for (final MapEntry<String, (Widget Function(), Type)> e in screens.entries) {
      testWidgets('${e.key} builds without exceptions ($lang)', (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': lang});
        await LocalStore.init();
        _phone(tester);
        final List<String> errs = _captureErrors();
        final ProviderContainer c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(profileProvider).updateProfile(name: 'Ashkan');
        c.read(settingsProvider).languageCode = lang;
        final GoRouter router =
            GoRouter(routes: <RouteBase>[GoRoute(path: '/', builder: (_, __) => e.value.$1())]);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: buildNxTheme(),
            routerConfig: router,
            locale: Locale(lang),
            supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ));
        await _frames(tester, 30);
        _release();
        expect(find.byType(e.value.$2), findsWidgets);
        expect(Directionality.of(tester.element(find.byType(e.value.$2).first)),
            lang == 'fa' ? TextDirection.rtl : TextDirection.ltr);
        expect(tester.takeException(), isNull);
        expect(errs, isEmpty);
        await _teardown(tester);
      });
    }
  }

  testWidgets('online lobby can be left (no ref use in dispose)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en'});
    await LocalStore.init();
    _phone(tester);
    final List<String> errs = _captureErrors();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: buildNxTheme(), home: const OnlineLobbyPage(gameId: 'pool8')),
    ));
    await _frames(tester, 10);
    final bool shown = find.byType(OnlineLobbyPage).evaluate().length == 1;
    await _teardown(tester);
    _release();
    expect(shown, isTrue);
    expect(tester.takeException(), isNull);
    expect(errs, isEmpty);
  });

  for (final String lang in <String>['en', 'fa']) {
    testWidgets('app router as guest: menus open their pages, online-only ones the sign-in screen ($lang)',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.lang': lang,
        'settings.auth_mode': 'guest',
        'settings.oracle_buddy': false,
        // Guided ORACLE tours already seen (a tour is a full-screen coach mark that would take the taps).
        'oracle_tour.seen.local': '["home","dock","rooms","social","settings","oracle","tournaments","games","shop",'
            '"chat","profile","game_setup.pool8","game_setup.finger_soccer"]',
      });
      await LocalStore.init();
      _phone(tester);
      final List<String> errs = _captureErrors();
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      if (!c.read(profileProvider).hasIdentity) c.read(profileProvider).updateProfile(name: 'Ashkan');
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const NexoraApp()));
      await _frames(tester, 20);
      _release(); // navigation failures must surface as test failures
      final GoRouter r = GoRouter.of(tester.element(find.byType(Navigator).first));
      r.go('/hub');
      await _frames(tester, 10);
      expect(find.byType(HubPage), findsOneWidget);

      // Dock GAME button -> Rooms (was bounced to /hub for guests).
      await tester.tap(find.descendant(of: find.byType(Nx2Dock), matching: find.text(lang == 'fa' ? 'بازی' : 'GAME')));
      await _frames(tester, 10);
      expect(find.byType(RoomsPage), findsOneWidget);
      expect(find.byType(HubPage, skipOffstage: false), findsOneWidget, reason: 'no duplicate home page');

      final Map<String, Type> expected = <String, Type>{
        '/world/nexora_arcade': ArcadePage,
        '/arcade/pool8': GameSetupPage,
        '/arcade/finger_soccer': GameSetupPage,
        '/social': SignInRequiredPage,
        '/world/orbit_network': SignInRequiredPage,
        '/tournaments': SignInRequiredPage,
        '/leaderboard': SignInRequiredPage,
        '/online/finger_soccer': SignInRequiredPage,
      };
      for (final MapEntry<String, Type> e in expected.entries) {
        r.go('/hub');
        await _frames(tester, 8);
        r.push(e.key);
        await _frames(tester, 12);
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
        expect(find.byType(HubPage, skipOffstage: false), findsOneWidget, reason: '${e.key}: no duplicate home page');
        // Back returns to the menu.
        r.pop();
        await _frames(tester, 10);
        expect(find.byType(HubPage), findsOneWidget, reason: '${e.key}: back');
      }
      expect(tester.takeException(), isNull);
      expect(errs, isEmpty);
      await _teardown(tester);
    });
  }
}
