import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/basketball_battle/core/basket_core.dart';

void main() {
  BasketCourt fresh() => BasketCourt(seed: 3)..countdown = 0;

  int shootAndWait(BasketCourt c, double sx, double sy) {
    final int before = c.score;
    expect(c.throwBall(sx, sy), isTrue);
    for (int i = 0; i < 240 && c.flying; i++) {
      c.step(1 / 60);
    }
    return c.score - before;
  }

  test('some swipes score 2 or 3 points and the ball respawns', () {
    int found = 0;
    for (double sy = -150; sy >= -340 && found == 0; sy -= 4) {
      for (double sx = -120; sx <= 120 && found == 0; sx += 4) {
        final BasketCourt c = fresh();
        final double need = c.hoopX - c.x;
        final int pts = shootAndWait(c, sx + need * 0.0, sy);
        if (pts > 0) {
          expect(pts == 2 || pts == 3, isTrue);
          expect(c.streak, 1);
          found++;
        }
      }
    }
    expect(found, 1, reason: 'a scoring swipe exists');
  });

  test('weak swipes are ignored, misses reset the streak', () {
    final BasketCourt c = fresh();
    expect(c.throwBall(0, -5), isFalse);
    c.streak = 2;
    shootAndWait(c, 400, -150);
    expect(c.streak, 0);
  });

  test('the clock ends the round and bots score sensibly', () {
    final BasketCourt c = fresh();
    for (int i = 0; i < 61 * 60; i++) {
      c.step(1 / 60);
    }
    expect(c.over, isTrue);
    expect(c.throwBall(0, -300), isFalse);
    final BasketBot easy = BasketBot(seed: 1, skill: 0.3), hard = BasketBot(seed: 1, skill: 0.92);
    for (int i = 0; i < 60 * 60; i++) {
      easy.step(1 / 60, 60);
      hard.step(1 / 60, 60);
    }
    expect(hard.score, greaterThan(easy.score));
    expect(hard.score, lessThan(150));
  });
}
