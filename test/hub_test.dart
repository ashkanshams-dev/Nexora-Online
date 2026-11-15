// v0.6 main screen: four edge panels open by tap and by drag, one at a time, and back closes them.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/net/supabase.dart' show Rec;
import 'package:nexora/ui/hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
  });
  final a = HubActions(profile: () {}, shop: () {}, daily: () {}, oracle: () {}, settings: () {}, chest: (_) {}, team: (_) {}, social: (_) {}, online: (_, [_]) {}, mode: (_) {}, room: (_) {});
  Future<MainHubState> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MainHub(a: a, dailyReady: true, chestReady: true, previewRooms: const <Rec>[]))));
    await t.pump();
    return t.state<MainHubState>(find.byType(MainHub));
  }

  testWidgets('tap a tab -> its panel springs open, another tab closes it', (t) async {
    final s = await pump(t);
    expect(s.open, isNull);
    await t.tap(find.text('بازی'));
    await _settle(t);
    expect(s.open, HubEdge.bottom);
    expect(s.c[HubEdge.bottom]!.value, closeTo(1, .01));
    await t.tap(find.text('پروفایل').last);
    await _settle(t);
    expect(s.open, HubEdge.top);
    expect(s.c[HubEdge.bottom]!.value, closeTo(0, .01));
    s.closeAll();
    await _settle(t);
    expect(s.open, isNull);
  });

  testWidgets('drag the left tab inwards opens MY TEAM', (t) async {
    final s = await pump(t);
    await t.drag(find.text('تیم'), const Offset(260, 0));
    await _settle(t);
    expect(s.open, HubEdge.left);
  });

  testWidgets('central panel has CREATE ROOM at the top', (t) async {
    await pump(t);
    expect(find.text('ساخت اتاق'), findsOneWidget);
    expect(find.text('CREATE ROOM'), findsOneWidget);
  });
}

/// v0.6.2: the main screen backdrop animates forever (pumpAndSettle never settles); springs finish well within 1.5 s.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
