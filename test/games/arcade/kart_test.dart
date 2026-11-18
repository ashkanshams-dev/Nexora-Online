import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/arcade_kit/arcade_meta.dart';
import 'package:nexora/games/kart_racing/core/kart_core.dart';

void main() {
  test('kart track is closed and deterministic per seed', () {
    final KartTrack a = KartTrack.generate(5), b = KartTrack.generate(5);
    expect(a.points.length, b.points.length);
    expect(a.at(3).x, b.at(3).x);
    expect(a.at(0).dist(a.at(a.n - 1)) < 80, isTrue);
  });

  test('bot-only race finishes all laps with a full ranking', () {
    final KartRace r = KartRace(seed: 42, racers: 4, botSkill: const <double>[0.9, 0.6, 0.3, 0.9]);
    int steps = 0;
    while (!r.allFinished && steps < 30 * 300) {
      r.step(1 / 30);
      steps++;
    }
    expect(r.allFinished, isTrue);
    expect(r.finishOrder.toSet().length, 4);
    expect(r.karts.every((Kart k) => k.lap >= 3), isTrue);
    expect(r.standings().first.seat, r.finishOrder.first);
  });

  test('shield absorbs a hit, otherwise the kart spins out', () {
    final KartRace r = KartRace(seed: 1, racers: 2);
    r.karts[1].shield = 3;
    r.hit(1);
    expect(r.karts[1].spin, 0);
    r.hit(1);
    expect(r.karts[1].spin > 0, isTrue);
  });

  test('daily seed and target are stable', () {
    expect(ArcadeDaily.seed('kart_racing', '2026-11-18'), ArcadeDaily.seed('kart_racing', '2026-11-18'));
    expect(ArcadeDaily.target('stack_tower', '2026-11-18') > 0, isTrue);
    expect(kArcadeIds.length, 20);
    expect(kArcadeDefs.length, 20);
  });
}
