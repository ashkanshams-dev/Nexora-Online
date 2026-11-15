// Dev-only v0.6.1 snapshots: kick-off on several pitches, goal close-up, aim arrow, ball speed trail.
// NX_SHOTS=/dir flutter test tool/snap/v061_test.dart   (default /tmp)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/assets.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/goal_skins.dart';
import 'package:nexora/game/render.dart';
import 'package:nexora/screens/match.dart' show ballShader;

final _dir = Platform.environment['NX_SHOTS'] ?? '/tmp';
const W = 412.0, H = 892.0, D = 2.0;

Future<ui.Image?> _opt(String? p) async => p == null ? null : await loadImage(p);

Future<(Engine, MatchRenderer)> _setup(int field, {String skin = 'classic', Team? a, Team? b}) async {
  final cfg = MatchCfg(field: field, ball: 0, forms: [0, 0], ai: true, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: [false, false], first: 0);
  final e = Engine(cfg);
  final f = kFields[field];
  final sk = kGoalSkins.firstWhere((s) => s.id == skin);
  final net = sk.net == null ? null : await loadImage(sk.net!);
  final im = MatchImages(await loadImage(kFIELD_IMG[f.id]!, width: 1100), await loadImage(ballImg(0), width: 256), await loadImage(teamImg(a ?? kTeams[0]), width: 192),
      await loadImage(teamImg(b ?? kTeams[1]), width: 192), await _opt(kARROW_IMG['head_e']), await _opt(kARROW_IMG['head_s']), await _opt(kARROW_IMG['shaft_e']),
      await _opt(kARROW_IMG['shaft_s']),
      skin: sk, net: net, aim: await _opt(kARROW_IMG['aim']));
  final r = MatchRenderer(e, im, 0, computeView(e, W, H, 86, 22), dpr: D, ballShader: await ballShader());
  await r.prepare();
  return (e, r);
}

Future<void> _shot(MatchRenderer r, String name, double t, {ui.Rect? crop}) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)..scale(D);
  r.render(c, t);
  var img = await rec.endRecording().toImage((W * D).round(), (H * D).round());
  if (crop != null) {
    final rec2 = ui.PictureRecorder();
    final k = 2.0;
    final c2 = ui.Canvas(rec2);
    c2.drawImageRect(img, ui.Rect.fromLTRB(crop.left * D, crop.top * D, crop.right * D, crop.bottom * D), ui.Rect.fromLTWH(0, 0, crop.width * D * k, crop.height * D * k),
        ui.Paint()..filterQuality = ui.FilterQuality.high);
    img = await rec2.endRecording().toImage((crop.width * D * k).round(), (crop.height * D * k).round());
  }
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$_dir/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fi in [0, 2, 14, 16]) {
    testWidgets('kickoff $fi', (t) async {
      await t.runAsync(() async {
        final (_, r) = await _setup(fi);
        await _shot(r, 'kickoff_${kFields[fi].id}', 0);
      });
    });
  }
  for (final sk in ['classic', 'gold']) {
    testWidgets('goal $sk', (t) async {
      await t.runAsync(() async {
        final (e, r) = await _setup(0, skin: sk);
        final v = r.v;
        // bottom goal close-up (screen space)
        final gy = e.goals[1].y * v.s + v.oy;
        await _shot(r, 'goal_closeup_$sk', 0, crop: ui.Rect.fromLTWH(W * .12, gy - 120, W * .76, 170));
      });
    });
  }

  testWidgets('aim arrow + speed trail', (t) async {
    await t.runAsync(() async {
      final (e, r) = await _setup(0);
      final d = e.bodies.firstWhere((b) => b.team == 0 && !identical(b, e.ball));
      for (final (tag, p) in [('short', .25), ('half', .55), ('full', 1.0)]) {
        e.drag = Drag(d, d.x, d.y, d.x + 60, d.y + LMAX * p * 1.0);
        r.render(ui.Canvas(ui.PictureRecorder()), 0);
        await _shot(r, 'aim_$tag', .1);
      }
      e.drag = null;
      final b = e.ball;
      b.vx = 1500;
      b.vy = -2200;
      b.px = b.x;
      b.py = b.y;
      await _shot(r, 'trail', .2, crop: ui.Rect.fromLTWH(W * .2, H * .25, W * .6, H * .35));
    });
  });

  // v0.6.2: new pitches with Premium Ultra discs
  for (final id in ['sansiro', 'campnou', 'blossom', 'frost', 'beach', 'autumn']) {
    testWidgets('v062 kickoff $id', (t) async {
      await t.runAsync(() async {
        final fi = kFields.indexWhere((f) => f.id == id);
        final ul = kTeams.where((x) => x.cat == 'ultra').toList();
        final (_, r) = await _setup(fi, a: ul[fi % ul.length], b: ul[(fi * 7) % ul.length]);
        await _shot(r, 'v062_kickoff_$id', 0);
      });
    });
  }
}
