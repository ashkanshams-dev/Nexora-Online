// Dev-only v0.6 pitch snapshots: flutter test tool/snap/pitch_v06_test.dart -> $NX_SHOTS/pitch_*.png (default /tmp)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/render.dart';
import 'package:nexora/screens/match.dart';

final _out = Platform.environment['NX_SHOTS'] ?? '/tmp';
final _fields = (Platform.environment['NX_FIELDS'] ?? '0').split(',').map(int.parse).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fi in _fields) {
    {
      testWidgets('pitch $fi', (t) async {
        await t.runAsync(() async {
          final cfg = MatchCfg(field: fi, ball: 0, forms: [0, 0], ai: true, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: [false, false], first: 0);
          final e = Engine(cfg);
          e.ball.x = e.ball.px = e.CX + 60;
          e.ball.y = e.ball.py = e.CY - 140;
          final im = await loadMatchImages(cfg, kTeams[0], kTeams[1]);
          const W = 412.0, H = 892.0;
          final v = computeView(e, W, H, 86, 22);
          final r = MatchRenderer(e, im, 0, v, dpr: 2);
          await r.prepare();
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec)..scale(2);
          r.render(c, 0);
          final img = await rec.endRecording().toImage((W * 2).round(), (H * 2).round());
          final bd = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/pitch_f$fi.png').writeAsBytesSync(bd!.buffer.asUint8List());
        });
      });
    }
  }
}
