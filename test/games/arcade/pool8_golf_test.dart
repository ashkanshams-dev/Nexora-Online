import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/mini_golf/core/golf_core.dart';
import 'package:nexora/games/pool8/core/pool8_core.dart';

void main() {
  group('8 ball pool blitz', () {
    test('break shot settles and passes or keeps the turn', () {
      final Pool8Blitz g = Pool8Blitz();
      final PoolShotReport? r = g.playNow(const PoolShot(dirX: 0, dirY: -1, power: 1));
      expect(r, isNotNull);
      expect(g.aiming || g.over, isTrue);
      expect(g.match.shotCount, 1);
    });

    test('shot clock foul gives the opponent ball in hand anywhere', () {
      final Pool8Blitz g = Pool8Blitz(shotClock: 5);
      g.playNow(const PoolShot(dirX: 0, dirY: -1, power: 1));
      final int before = g.current;
      bool fired = false;
      for (int i = 0; i < 400 && !fired; i++) {
        fired = g.tickClock(1 / 60);
      }
      expect(fired, isTrue);
      g.timeout();
      expect(g.current, 1 - before);
      expect(g.match.ballInHand, isTrue);
      expect(g.match.kitchenOnly, isFalse);
      expect(g.nearestFreeSpot(PoolConfig.tableW / 2, PoolConfig.tableH / 2), isNotNull);
    });

    test('bots finish a whole match deterministically', () {
      String play() {
        final Pool8Blitz g = Pool8Blitz();
        final math.Random rng = math.Random(4);
        int shots = 0;
        while (!g.over && shots < 160) {
          final PoolShot s = PoolBotPlanner(match: g.match, level: PoolBotLevel.hard, rng: rng).plan();
          if (g.playNow(s) == null) g.timeout();
          shots++;
        }
        return '${g.winner}|${g.match.stateHash}|$shots';
      }

      final String a = play();
      expect(a, play());
      expect(a.startsWith('null'), isFalse, reason: 'a hard-bot match must end');
    });
  });

  group('mini golf', () {
    test('a straight putt on hole 1 can drop and the next hole starts', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      int guard = 0;
      while (g.hole == 0 && guard++ < 10) {
        final GBall b = g.balls[0];
        final double a = math.atan2(g.h.cup.y - b.y, g.h.cup.x - b.x);
        final double d = math.sqrt(math.pow(g.h.cup.y - b.y, 2) + math.pow(g.h.cup.x - b.x, 2));
        g.shoot(a, (d / 520).clamp(0.08, 1.0));
        g.runToEnd();
      }
      expect(g.hole, 1);
      expect(g.cards[0].single, lessThanOrEqualTo(kMaxStrokes + 1));
    });

    test('water costs a stroke and resets the ball', () {
      final GolfMatch g = GolfMatch(players: 1, seed: 2);
      g.hole = 5;
      g.balls = <GBall>[GBall(80, 330)];
      g.shoot(-math.pi / 2, 0.18);
      g.runToEnd();
      expect(g.balls[0].strokes, 2);
      expect(g.balls[0].y, closeTo(330, 0.001));
    });

    test('max strokes caps a hole and bots finish all 9 holes', () {
      final GolfMatch g = GolfMatch(players: 3, seed: 7);
      final math.Random rng = math.Random(1);
      int shots = 0;
      while (!g.over && shots < 300) {
        final (double a, double p) = g.botShot(rng, 0.9, samples: 16);
        g.shoot(a, p);
        g.runToEnd();
        shots++;
      }
      expect(g.over, isTrue);
      for (final List<int> c in g.cards) {
        expect(c.length, 9);
        expect(c.every((int s) => s >= 1 && s <= kMaxStrokes + 1), isTrue);
      }
      expect(g.ranking().toSet().length, 3);
    });

    test('same shots replay identically (online determinism)', () {
      String run() {
        final GolfMatch g = GolfMatch(players: 2, seed: 3);
        for (int i = 0; i < 12 && !g.over; i++) {
          g.shoot(-math.pi / 2 + (i % 5 - 2) * 0.13, 0.3 + (i % 4) * 0.15);
          g.runToEnd();
        }
        return g.stateKey();
      }

      expect(run(), run());
    });
  });
}
