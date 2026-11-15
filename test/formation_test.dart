// v0.6.1: formation change end to end. The owner reported many times that picking a formation "does nothing".
// Root cause: the team screen's picker was a const child of a ListenableBuilder, so it never rebuilt after a tap
// (the pick was saved but the screen kept showing the old one). These tests cover: the picker UI reacts and
// persists, a launch built from the saved profile places the discs in that formation at kick-off, and a captain's
// mid-match change applies at the next kick-off / reset.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/screens/setup.dart';
import 'package:nexora/screens/team.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Expected kick-off position of slot [i] of formation [fi] for [team] (0 = bottom half, 1 = top half).
(double, double) expectedSlot(Engine e, int fi, int team, int i) {
  final sl = slots(fi)[i];
  final ins = e.tu.discR + 6;
  final x = e.Fl + ins + sl[0] * (e.Fr - e.Fl - 2 * ins);
  final y = team != 0 ? e.Ft + sl[1] * (e.Fb - e.Ft) : e.Fb - sl[1] * (e.Fb - e.Ft);
  return (x, y);
}

void expectFormation(Engine e, int team, int fi) {
  final ds = e.bodies.where((b) => b.team == team).toList();
  expect(ds.length, slots(fi).length);
  for (var i = 0; i < ds.length; i++) {
    final (x, y) = expectedSlot(e, fi, team, i);
    expect(ds[i].x, closeTo(x, 1e-6), reason: 'team $team form ${kForms[fi].code} disc $i x');
    expect(ds[i].y, closeTo(y, 1e-6), reason: 'team $team form ${kForms[fi].code} disc $i y');
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
    for (final (f, a) in [('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf'), ('Orbitron', 'assets/fonts/Orbitron-VF.ttf')]) {
      await (FontLoader(f)..addFont(rootBundle.load(a))).load();
    }
  });

  test('formations are really different (every pair differs in at least one slot)', () {
    for (var a = 0; a < kForms.length; a++) {
      for (var b = a + 1; b < kForms.length; b++) {
        expect(jsonEncode(slots(a)) == jsonEncode(slots(b)), isFalse, reason: '${kForms[a].code} vs ${kForms[b].code}');
      }
    }
  });

  test('saved formation -> quick match launch -> discs stand in that formation at kick-off', () {
    final opp = kTeams.firstWhere((x) => x.cat == 'nat');
    for (var fi = 0; fi < kForms.length; fi++) {
      Store.i.set((p) => p.form = fi);
      final l = buildLaunch(ModeKey.quick, Store.i.p, lvl: 1, rule: 'g3', tt: 15, opp: opp);
      expect(l.cfg.forms[0], fi);
      final e = Engine(l.cfg);
      expectFormation(e, 0, fi);
      expectFormation(e, 1, l.cfg.forms[1]);
    }
    // local 2P: both sides use the player's formation
    Store.i.set((p) => p.form = 2);
    final l = buildLaunch(ModeKey.local, Store.i.p, lvl: 1, rule: 'g3', tt: 15, opp: opp);
    final e = Engine(l.cfg);
    expectFormation(e, 0, 2);
    expectFormation(e, 1, 2);
  });

  test('saved formation survives a reload (persisted profile json)', () {
    Store.i.set((p) => p.form = 4);
    final p2 = Profile.fromJson(jsonDecode(jsonEncode(Store.i.p.toJson())) as Map<String, dynamic>);
    expect(p2.form, 4);
  });

  test('captain changes formation mid-match: at once before the first shot, else at the next reset', () {
    final cfg = MatchCfg(field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 9, matchTime: 0, turnTime: 0, vip: [false, false], first: 0);
    final e = Engine(cfg);
    expectFormation(e, 0, 0);
    e.setFormation(0, 5); // nobody shot yet: re-placed immediately
    expectFormation(e, 0, 5);
    // a shot is fired: the change must wait for the next kick-off
    final d = e.bodies.firstWhere((b) => b.team == 0);
    e.fire(d, 0, -100, 100);
    e.setFormation(0, 2);
    e.setFormation(1, 3);
    for (var i = 0; i < 10; i++) {
      e.update(1 / 60);
    }
    expect(e.bodies.where((b) => b.team == 1).first.y, isNot(closeTo(expectedSlot(e, 3, 1, 0).$2, 1e-6)));
    e.reset(1); // goal / restart
    expectFormation(e, 0, 2);
    expectFormation(e, 1, 3);
  });

  testWidgets('team screen formation picker shows the new pick immediately and saves it', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    Store.i.set((p) => p.form = 0);
    await t.pumpWidget(const MaterialApp(home: TeamScreen(initial: 'form')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('${kForms[0].code} • ${kForms[0].name}'), findsOneWidget);
    // tap the «انتخاب» button of formation 3 (grid order = kForms order)
    final btns = find.text('انتخاب');
    expect(btns, findsNWidgets(kForms.length - 1));
    await t.drag(find.byType(ListView).last, const Offset(0, -500));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(btns.at(2));
    await t.pump(const Duration(milliseconds: 500));
    expect(Store.i.p.form, 3);
    expect(find.text('${kForms[3].code} • ${kForms[3].name}'), findsOneWidget, reason: 'header must follow the pick');
    expect(find.text('انتخاب شده'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
