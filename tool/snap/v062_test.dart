// Dev-only v0.6.2 snapshots: Premium Ultra discs in My Teams and in the shop.
//   NX_SHOTS=/path flutter test tool/snap/v062_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/net/supabase.dart' show Rec;
import 'package:nexora/ui/hub.dart';
import 'package:nexora/screens/shop.dart';
import 'package:nexora/screens/team.dart';
import 'package:shared_preferences/shared_preferences.dart';


final _out = Platform.environment['NX_SHOTS'] ?? '/tmp';

Future<void> _fonts() async {
  for (final (f, a) in [('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf'), ('Orbitron', 'assets/fonts/Orbitron-VF.ttf'), ('Exo2', 'assets/fonts/Exo2-VF.ttf'), ('Oxanium', 'assets/fonts/Oxanium-VF.ttf')]) {
    final l = FontLoader(f)..addFont(rootBundle.load(a));
    await l.load();
  }
  // Material icons for the header / bar glyphs
  final mi = File('${Platform.environment['FLUTTER_ROOT'] ?? '/tmp/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (mi.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(mi.readAsBytesSync())));
    await l.load();
  }
}

final _rb = GlobalKey();

Future<void> snap(WidgetTester t, String name, Widget w, {Size phys = const Size(1080, 2340), double dpr = 2.625, Future<void> Function()? after}) async {
  t.view.physicalSize = phys;
  t.view.devicePixelRatio = dpr;
  t.view.padding = const FakeViewPadding(top: 63, bottom: 42);
  await t.pumpWidget(RepaintBoundary(key: _rb, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Exo2'), home: w)));
  await t.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 50));
    }
  });
  if (after != null) await after();
  await t.pump(const Duration(milliseconds: 1200));
  await t.runAsync(() async {
    final ro = _rb.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final im = await ro.toImage(pixelRatio: dpr);
    final bd = await im.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
  });
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}


void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
    await _fonts();
  });
  testWidgets('team ultra', (t) async => snap(t, 'team_ultra', const TeamScreen(), phys: const Size(1080, 3200), after: () async {
        await t.tap(find.text('پریمیوم اولترا').first);
        await t.pump(const Duration(milliseconds: 600));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
        await t.pump(const Duration(milliseconds: 600));
      }));
  testWidgets('shop ultra', (t) async => snap(t, 'shop_ultra', ShopScreen(onChest: (_) {}), phys: const Size(1080, 3600), after: () async {
        final f = find.text('Premium Ultra');
        if (f.evaluate().isNotEmpty) {
          await t.ensureVisible(f.first);
          await t.tap(f.first);
        }
        await t.pump(const Duration(milliseconds: 600));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
        await t.pump(const Duration(milliseconds: 600));
      }));

  final rooms = [
    for (final (n, h, lv, pl, st) in [('فینال کهکشانی', 'Sara', 12, 1, 'waiting'), ('Golden League', 'omid', 8, 2, 'playing'), ('NEXORA Night', 'Ghost', 21, 1, 'waiting')])
      Rec({'id': n, 'name': n, 'host_name': h, 'host_level': lv, 'host_avatar': 'club${lv % 9}', 'mode': '1v1', 'kind': 'casual', 'players': pl, 'capacity': 2, 'spectators': 1, 'status': st, 'settings': {'goals': 3, 'turn': 15, 'field': 0}}),
  ];
  final a = HubActions(profile: () {}, shop: () {}, daily: () {}, oracle: () {}, settings: () {}, chest: (_) {}, team: (_) {}, social: (_) {}, online: (_, [_]) {}, mode: (_) {}, room: (_) {});
  Widget hub(HubEdge? e) => Scaffold(backgroundColor: const Color(0xff0a0626), body: MainHub(a: a, dailyReady: true, chestReady: false, initialOpen: e, previewRooms: rooms));
  testWidgets('hub bg frame A', (t) async => snap(t, 'hub_bg_a', hub(null)));
  testWidgets('hub bg frame B', (t) async => snap(t, 'hub_bg_b', hub(null), after: () async => t.pump(const Duration(seconds: 9))));
  testWidgets('hub left open', (t) async => snap(t, 'hub_left_open', hub(HubEdge.left)));
  testWidgets('hub left picked', (t) async => snap(t, 'hub_left_picked', hub(HubEdge.left), after: () async {
        hubPicked.value = 'توپ';
        await t.pump(const Duration(milliseconds: 500));
      }));
  testWidgets('hub left swiping', (t) async {
    hubPicked.value = null;
    await snap(t, 'hub_left_swiping', hub(HubEdge.left), after: () async {
      // drag the left tab back towards the edge and hold (mid-swipe)
      final tab = find.text('تیم').last;
      final g = await t.startGesture(t.getCenter(tab));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-12, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      await t.pump(const Duration(milliseconds: 250));
      _held = g;
    });
    await _held?.up();
  });
}
TestGesture? _held;
