import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/online/cup_logic.dart';

void main() {
  group('bracket', () {
    test('size and rounds', () {
      expect([2, 3, 4, 5, 8, 9, 33, 64].map(bracketSize).toList(), [2, 4, 4, 8, 8, 16, 64, 64]);
      expect([2, 3, 5, 16, 17, 64].map(bracketRounds).toList(), [1, 2, 3, 4, 5, 6]);
    });
    test('standard seed order', () {
      expect(seedOrder(4), [1, 4, 2, 3]);
      expect(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
      final o = seedOrder(64);
      expect(o.toSet().length, 64);
      for (var i = 0; i < 64; i += 2) {
        expect(o[i] + o[i + 1], 65); // every pair sums to size + 1
        expect(o[i] < o[i + 1], isTrue); // better seed first, so a bye is always the second slot
      }
    });
    test('byes: only top seeds get them, never two byes in one pairing', () {
      for (var n = 2; n <= kCupMaxPlayers; n++) {
        final r = firstRound(n);
        final byes = r.where((p) => p.$2 == null).toList();
        expect(byes.length, bracketSize(n) - n, reason: 'n=$n');
        expect(byes.map((p) => p.$1).toSet(), {for (var s = 1; s <= bracketSize(n) - n; s++) s}, reason: 'n=$n');
        final seen = <int>{for (final p in r) ...[p.$1, if (p.$2 != null) p.$2!]};
        expect(seen, {for (var s = 1; s <= n; s++) s}, reason: 'everyone placed exactly once, n=$n');
      }
    });
    test('5 players: 3 byes, one real round-1 pairing (4 vs 5)', () {
      expect(firstRound(5), [(1, null), (4, 5), (2, null), (3, null)]);
    });
    test('places with the better seed always winning', () {
      int best(int a, int b) => a < b ? a : b;
      expect(simulatePlaces(2, best), [1, 2, null]);
      expect(simulatePlaces(3, best), [1, 2, 3]); // 3rd = the only semi loser, no 3rd-place match
      expect(simulatePlaces(5, best), [1, 2, 3]);
      expect(simulatePlaces(64, best), [1, 2, 3]);
      int worst(int a, int b) => a > b ? a : b;
      expect(simulatePlaces(8, worst), [8, 7, 6]);
    });
    test('round names', () {
      expect(roundNameFa(6, 6), 'فینال');
      expect(roundNameFa(5, 6), 'نیمه‌نهایی');
      expect(roundNameFa(1, 6), 'دور ۱');
      expect(roundNameFa(3, 3, third: true), 'رده‌بندی');
    });
  });

  group('series', () {
    test('single game', () {
      expect(playSeries(1, [(3, 1)]), (1, 1));
      expect(playSeries(1, [(0, 3)]), (2, 1));
    });
    test('best of 3 ends at 2 wins', () {
      expect(playSeries(3, [(3, 0), (3, 2)]), (1, 2));
      expect(playSeries(3, [(3, 0), (1, 3), (2, 3)]), (2, 3));
    });
    test('best of 2: 1-1 goes to goal difference, then a decider', () {
      expect(playSeries(2, [(3, 0), (2, 3)]), (1, 2)); // 1-1, goals 5:3
      expect(playSeries(2, [(3, 2), (2, 3)]), (0, 2)); // level on everything -> decider needed
      expect(playSeries(2, [(3, 2), (2, 3), (1, 3)]), (2, 3));
      expect(playSeries(2, [(3, 0), (3, 1)]), (1, 2));
    });
    test('clinched early only when the lead is bigger than the games left', () {
      expect(seriesWinner(5, 3, 0, 9, 0, 3), 1);
      expect(seriesWinner(5, 2, 0, 6, 0, 2), 0);
      expect(seriesWinner(4, 2, 0, 6, 0, 2), 0); // 2-0 in 4 games can still be 2-2
      expect(seriesWinner(4, 3, 0, 9, 0, 3), 1);
    });
    test('draws do not count as wins; after N+3 games the higher seed advances', () {
      expect(seriesWinner(1, 0, 0, 1, 1, 1), 0);
      expect(seriesWinner(1, 0, 0, 3, 3, 4), 1);
    });
    test('format labels', () {
      expect(formatFa(1), 'تک بازی');
      expect(formatFa(3), 'بهترین ۳');
      expect(formatFa(2), 'دو بازی (مجموع)');
    });
  });

  group('prize', () {
    test('default split 60/30/10 of 100', () => expect(prizeShares(100, kCupDefaultSplit), [60, 30, 10]));
    test('remainder goes to first and the total is exact', () {
      for (var p = 0; p <= kCupMaxPrize; p++) {
        for (final s in kCupSplits) {
          final a = prizeShares(p, s);
          expect(a.reduce((x, y) => x + y), p);
          expect(a.every((x) => x >= 0), isTrue);
          expect(a[0] >= a[1] && a[1] >= a[2], isTrue);
        }
      }
      expect(prizeShares(7, [50, 30, 20]), [4, 2, 1]);
      expect(prizeShares(1, [60, 30, 10]), [1, 0, 0]);
    });
    test('split validation', () {
      expect(kCupSplits.every(validSplit), isTrue);
      expect(validSplit([30, 60, 10]), isFalse);
      expect(validSplit([60, 30, 20]), isFalse);
    });
  });

  group('jalali + tehran', () {
    test('known dates', () {
      expect(gregorianToJalali(2026, 11, 15), (1405, 8, 24));
      expect(gregorianToJalali(2026, 3, 21), (1405, 1, 1));
      expect(gregorianToJalali(2025, 3, 20), (1403, 12, 30));
      expect(jalaliToGregorian(1405, 8, 24), (2026, 11, 15));
      expect(jalaliToGregorian(1403, 12, 30), (2025, 3, 20));
    });
    test('round trip over 3 years', () {
      var d = DateTime.utc(2025, 1, 1);
      for (var i = 0; i < 1100; i++) {
        final (jy, jm, jd) = gregorianToJalali(d.year, d.month, d.day);
        expect(jalaliToGregorian(jy, jm, jd), (d.year, d.month, d.day));
        d = d.add(const Duration(days: 1));
      }
    });
    test('Tehran wall time <-> UTC (+03:30)', () {
      final u = fromTehranJalali(1405, 8, 24, 18, 30);
      expect(u, DateTime.utc(2026, 11, 15, 15, 0));
      expect(tehranClock(u), '۱۸:۳۰');
      expect(jalaliLabel(u), 'یکشنبه ۲۴ آبان · ۱۸:۳۰');
      // just after Tehran midnight is still the previous UTC day
      expect(jalaliLabel(DateTime.utc(2026, 11, 15, 21, 0), weekday: false), '۲۵ آبان · ۰۰:۳۰');
    });
    test('countdown', () {
      expect(faCountdown(const Duration(minutes: 3, seconds: 4)), '۳ دقیقه و ۴ ثانیه');
      expect(faCountdown(const Duration(seconds: 3)), '۳ ثانیه');
    });
  });
}
