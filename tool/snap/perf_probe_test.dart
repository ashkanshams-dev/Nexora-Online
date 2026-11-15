// Dev-only CPU cost probe: engine step + renderer frame recording (no GPU). flutter test tool/snap/perf_probe_test.dart
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/assets.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/render.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('perf', (t) async {
    await t.runAsync(() async {
      final cfg = MatchCfg(field: kDefaultField, ball: 0, forms: [0, 0], ai: true, aiLvl: 2, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 1);
      final e = Engine(cfg);
      final f = kFields[cfg.field];
      final im = MatchImages(await loadImage(kFIELD_IMG[f.id]!, width: 1100), await loadImage(ballImg(0), width: 256), await loadImage(teamImg(kTeams[0]), width: 192),
          await loadImage(teamImg(kTeams[1]), width: 192), null, null, null, null);
      final r = MatchRenderer(e, im, 0, computeView(e, 412, 892, 86, 22), dpr: 2.75);
      await r.prepare();
      final sw = Stopwatch(), sr = Stopwatch();
      for (var i = 0; i < 1800; i++) {
        sw.start();
        e.update(1 / 60);
        e.clearEvents();
        sw.stop();
        sr.start();
        final rec = ui.PictureRecorder();
        r.render(ui.Canvas(rec), i / 60);
        rec.endRecording().dispose();
        sr.stop();
      }
      // ignore: avoid_print
      print('per frame: engine ${(sw.elapsedMicroseconds / 1800).toStringAsFixed(0)} us, render record ${(sr.elapsedMicroseconds / 1800).toStringAsFixed(0)} us, shots ${e.shots}');
    });
  });
}
