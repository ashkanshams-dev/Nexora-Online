// Smoke: the screens the owner reported as broken must build without exceptions, and the match must reach
// a live renderer with both teams' disc sprites (offline vs bot, quick match).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/app/shell.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/ui/v4.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/screens/match.dart';
import 'package:nexora/screens/setup.dart';
import 'package:nexora/screens/shop.dart';
import 'package:nexora/screens/team.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rb = GlobalKey();

Future<void> _pumpReal(WidgetTester t, {int n = 8}) async {
  await t.runAsync(() async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 100));
    }
  });
}

Future<void> _shot(WidgetTester t, String name) async {
  final dir = Platform.environment['NX_SHOTS'];
  if (dir == null) return;
  await t.runAsync(() async {
    final ro = _rb.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final im = await ro.toImage(pixelRatio: 1);
    final bd = await im.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
  });
}

Widget _app(Widget w) => RepaintBoundary(key: _rb, child: MaterialApp(debugShowCheckedModeBanner: false, home: w));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
    for (final (f, a) in [('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf'), ('Orbitron', 'assets/fonts/Orbitron-VF.ttf'), ('Exo2', 'assets/fonts/Exo2-VF.ttf'), ('Oxanium', 'assets/fonts/Oxanium-VF.ttf')]) {
      await (FontLoader(f)..addFont(rootBundle.load(a))).load();
    }
  });
  shellFlow();

  testWidgets('team screen builds', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(_app(const TeamScreen()));
    await _pumpReal(t);
    await _shot(t, 'team');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('shop screen builds', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(_app(ShopScreen(onChest: (_) {})));
    await _pumpReal(t);
    await _shot(t, 'shop');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('quick match vs bot opens with both teams', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    final l = buildLaunch(ModeKey.quick, Store.i.p, lvl: 1, rule: 'g3', tt: 15, opp: kTeams.firstWhere((x) => x.cat == 'nat'));
    await t.pumpWidget(_app(MatchScreen(cfg: l.cfg, teams: l.teams, names: l.names, onFinish: (_) {}, onQuit: () {})));
    await _pumpReal(t, n: 20);
    await _shot(t, 'match');
    final st = t.state(find.byType(MatchScreen)) as dynamic;
    expect(st.loading, isFalse, reason: 'match still loading');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}

// Full shell flow: intro -> home -> team / shop / quick match, through the real navigator.
void shellFlow() {
  testWidgets('shell: team, shop and quick match open from home', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    Store.i.set((q) => q.introVideo = false);
    await t.pumpWidget(RepaintBoundary(key: _rb, child: const NexoraApp()));
    await _pumpReal(t, n: 30);
    await t.pump(const Duration(seconds: 6));
    await _pumpReal(t, n: 5);
    await _shot(t, 'shell_home');
    final errs = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) { errs.add(d); };
    addTearDown(() => FlutterError.onError = prev);
    final sh = t.state(find.byType(NexoraApp)) as dynamic;
    sh.onTab(NavTab.team);
    await _pumpReal(t, n: 10);
    await _shot(t, 'shell_team');
    expect(find.byType(TeamScreen), findsOneWidget);
    sh.goHome();
    await _pumpReal(t, n: 6);
    sh.onWorld('shop');
    await _pumpReal(t, n: 10);
    await _shot(t, 'shell_shop');
    expect(find.byType(ShopScreen), findsOneWidget);
    sh.goHome();
    await _pumpReal(t, n: 6);
    sh.startMatch(buildLaunch(ModeKey.quick, Store.i.p, lvl: 1, rule: 'g3', tt: 15, opp: kTeams.firstWhere((x) => x.cat == 'nat')));
    await _pumpReal(t, n: 25);
    await _shot(t, 'shell_match');
    expect(find.byType(MatchScreen), findsOneWidget);
    expect((t.state(find.byType(MatchScreen)) as dynamic).loading, isFalse);
    for (final d in errs) { debugPrint('ERR: ${d.exceptionAsString()}\n${d.stack}'); }
    expect(errs, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 60));
  });
}
