import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/bomb_arena/core/bomb_core.dart';
import 'package:nexora/games/obstacle_race/core/obstacle_core.dart';

void main() {
  test('obstacle race ends with a full ranking', () {
    final ObstacleRace r = ObstacleRace(seed: 2, count: 4, botSkill: const <double>[0.3, 0.6, 0.9, 0.9]);
    int steps = 0;
    while (!r.over && steps < 30 * 600) {
      r.step(1 / 30);
      steps++;
    }
    expect(r.over, isTrue);
    expect(r.ranking().toSet().length, 4);
  });

  test('falling into a pit eliminates', () {
    final ObstacleRace r = ObstacleRace(seed: 9, count: 2)..countdown = 0;
    final Obstacle pit = r.obstacles.firstWhere((Obstacle o) => o.kind == ObKind.pit);
    final Runner p = r.runners[0];
    r.cam = pit.y - 100;
    p.x = pit.x + pit.w / 2;
    p.y = pit.y + pit.h / 2;
    r.step(1 / 60, simulate: <int>{0});
    expect(p.alive, isFalse);
  });

  test('bomb blast destroys crates, chains and knocks out', () {
    final BombArena a = BombArena(seed: 1, count: 2)..countdown = 0;
    final BPlayer p = a.players[0];
    expect(a.placeBomb(0), isTrue);
    expect(a.placeBomb(0), isFalse, reason: 'one bomb at a time');
    for (int i = 0; i < 30 * 3; i++) {
      a.step(1 / 30);
    }
    expect(p.alive, isFalse, reason: 'standing on your own bomb is fatal');
    expect(a.ranking().first, 1);
  });

  test('bot-only bomb arena finishes', () {
    final BombArena a = BombArena(seed: 4, count: 4, botSkill: const <double>[0.9, 0.6, 0.6, 0.9]);
    int steps = 0;
    while (!a.over && steps < 30 * 200) {
      a.step(1 / 30);
      steps++;
    }
    expect(a.over, isTrue);
    final BombArena b = BombArena(seed: 4, count: 2);
    b.applySnapshot(a.snapshot());
    expect(b.grid.map((List<String> r) => r.join()).join(), a.grid.map((List<String> r) => r.join()).join());
  });
}
