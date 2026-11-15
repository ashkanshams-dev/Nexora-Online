// Cups (tournament v3) pure logic, shared by the UI and the tests. The server (supabase/cups.sql) is the authority;
// these functions mirror its rules exactly so the bracket / series / prize the app shows are what the server does.
//   * single elimination, 2..64 players, bracket size = next power of two, byes go to the best seeds
//   * a pairing is a series of N games (1..9): clinched when the lead is bigger than the games left; after N games a
//     tie on wins goes to goal difference, then sudden-death deciders; after N+3 games the higher seed advances
//   * prize 0..100 gems escrowed from the creator, split between places 1-3 (floor, remainder to 1st)
//   * times are stored in UTC and shown in the Persian (Jalali) calendar, Tehran time (UTC+03:30, no DST since 2022)

/// Lineup window (seconds) before every game of a series: players pick formation and team. Short on purpose (owner
/// asked for 3 s); the server value is cup_cfg().lineup_s in supabase/cups.sql. Change both together.
const int kCupLineupSeconds = 3;

/// Pause after a game before the next lineup window (server cup_cfg().gap_s).
const int kCupGapSeconds = 12;
const int kCupCheckinMinutes = 15; // check-in opens / reminder goes out this long before the start
const int kCupReplaceMinutes = 5; // last minutes in which waitlisted players replace absentees
const int kCupNoShowMinutes = 5; // a player who does not enter a ready pairing in time loses by walkover
const int kCupMaxPlayers = 64;
const int kCupMaxPrize = 100;
const int kCupMaxGames = 9;
const int kCupGameMinutes = 6, kCupBufferMinutes = 4;
const List<int> kCupDefaultSplit = [60, 30, 10];
const List<List<int>> kCupSplits = [
  [100, 0, 0],
  [70, 30, 0],
  [60, 30, 10],
  [50, 30, 20],
];

// ------------------------------------------------------------------ bracket
int bracketSize(int n) {
  var s = 2;
  while (s < n) {
    s *= 2;
  }
  return s;
}

int bracketRounds(int n) {
  var r = 1, s = 2;
  while (s < n) {
    s *= 2;
    r++;
  }
  return r;
}

/// Standard seed order: pairs (o[2i], o[2i+1]) meet in round 1; seed 1 and 2 can only meet in the final.
List<int> seedOrder(int size) {
  if (size < 2) return [1];
  var o = [1, 2];
  while (o.length < size) {
    final l = o.length;
    o = [for (final s in o) ...[s, 2 * l + 1 - s]];
  }
  return o;
}

/// Round-1 pairings for n players: (seedA, seedB) with seedB = null for a bye.
List<(int, int?)> firstRound(int n) {
  final size = bracketSize(n), o = seedOrder(size);
  return [for (var i = 0; i < size ~/ 2; i++) (o[2 * i], o[2 * i + 1] <= n ? o[2 * i + 1] : null)];
}

/// Minutes between round starts (one series + buffer), server _cup_slot_min.
int roundSlotMinutes(int games) => games * kCupGameMinutes + kCupBufferMinutes;

/// Simulates a whole bracket with a winner rule (by seed) and returns the seeds at places 1..3 (null = nobody),
/// the same way the server fills the bracket (byes advance, semi losers meet in the 3rd-place match).
List<int?> simulatePlaces(int n, int Function(int a, int b) winnerOf) {
  final size = bracketSize(n);
  var cur = <int?>[for (final p in firstRound(n)) ...[p.$1, p.$2]];
  List<int?> semiLosers = [];
  while (cur.length > 1) {
    final next = <int?>[];
    final losers = <int?>[];
    for (var i = 0; i < cur.length; i += 2) {
      final a = cur[i], b = cur[i + 1];
      if (a == null || b == null) {
        next.add(a ?? b);
        losers.add(null);
      } else {
        final w = winnerOf(a, b);
        next.add(w);
        losers.add(w == a ? b : a);
      }
    }
    if (cur.length == 4) semiLosers = losers;
    if (cur.length == 2) {
      final third = size >= 4
          ? (semiLosers.whereType<int>().length == 2 ? winnerOf(semiLosers[0]!, semiLosers[1]!) : semiLosers.whereType<int>().firstOrNull)
          : null;
      return [next.first, losers.first, third];
    }
    cur = next;
  }
  return [cur.first, null, null];
}

String roundNameFa(int round, int rounds, {bool third = false}) {
  if (third) return 'رده‌بندی';
  final left = rounds - round; // 0 = final
  return switch (left) {
    0 => 'فینال',
    1 => 'نیمه‌نهایی',
    2 => 'یک‌چهارم نهایی',
    3 => 'یک‌هشتم نهایی',
    _ => faDigits('دور $round'),
  };
}

// ------------------------------------------------------------------ series
/// 1 / 2 = that side won the series, 0 = play another game (server _cup_series_winner).
int seriesWinner(int games, int w1, int w2, int g1, int g2, int played) {
  final rem = games - played < 0 ? 0 : games - played;
  if (w1 > w2 + rem) return 1;
  if (w2 > w1 + rem) return 2;
  if (played >= games) {
    if (g1 > g2) return 1;
    if (g2 > g1) return 2;
    if (played >= games + 3) return 1;
  }
  return 0;
}

/// Plays a list of game scores through the series rule; returns (winner side, games used).
(int, int) playSeries(int games, List<(int, int)> scores) {
  var w1 = 0, w2 = 0, g1 = 0, g2 = 0, n = 0;
  for (final (a, b) in scores) {
    n++;
    g1 += a;
    g2 += b;
    if (a > b) w1++;
    if (b > a) w2++;
    final w = seriesWinner(games, w1, w2, g1, g2, n);
    if (w != 0) return (w, n);
  }
  return (0, n);
}

String formatFa(int games) => switch (games) {
      1 => 'تک بازی',
      2 => 'دو بازی (مجموع)',
      _ => faDigits(games.isOdd ? 'بهترین $games' : '$games بازی (مجموع)'),
    };

// ------------------------------------------------------------------ prize
/// Gems for places 1..3 (server _cup_shares).
List<int> prizeShares(int prize, List<int> split) {
  final a = [for (var i = 0; i < 3; i++) prize * split[i] ~/ 100];
  a[0] += prize - a[0] - a[1] - a[2];
  return a;
}

bool validSplit(List<int> s) => s.length == 3 && s[2] >= 0 && s[0] >= s[1] && s[1] >= s[2] && s[0] + s[1] + s[2] == 100;

// ------------------------------------------------------------------ Jalali calendar + Tehran time
const Duration kTehranOffset = Duration(hours: 3, minutes: 30);
const kJalaliMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
// DateTime.weekday: 1 = Monday ... 7 = Sunday
const kFaWeekdays = {1: 'دوشنبه', 2: 'سه‌شنبه', 3: 'چهارشنبه', 4: 'پنجشنبه', 5: 'جمعه', 6: 'شنبه', 7: 'یکشنبه'};

(int, int, int) gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = days < 186 ? 1 + days % 31 : 1 + (days - 186) % 30;
  return (jy, jm, jd);
}

(int, int, int) jalaliToGregorian(int jy, int jm, int jd) {
  jy += 1595;
  var days = -355668 + 365 * jy + (jy ~/ 33) * 8 + ((jy % 33) + 3) ~/ 4 + jd + (jm < 7 ? (jm - 1) * 31 : (jm - 7) * 30 + 186);
  var gy = 400 * (days ~/ 146097);
  days %= 146097;
  if (days > 36524) {
    days--;
    gy += 100 * (days ~/ 36524);
    days %= 36524;
    if (days >= 365) days++;
  }
  gy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    gy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  var gd = days + 1;
  final leap = (gy % 4 == 0 && gy % 100 != 0) || gy % 400 == 0;
  final ml = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var gm = 0;
  while (gm < 12 && gd > ml[gm]) {
    gd -= ml[gm];
    gm++;
  }
  return (gy, gm + 1, gd);
}

/// Wall-clock Tehran fields of a UTC instant (returned as a UTC DateTime carrying Tehran's numbers).
DateTime tehranWall(DateTime t) => t.toUtc().add(kTehranOffset);

/// UTC instant of a Tehran wall-clock time given in the Jalali calendar.
DateTime fromTehranJalali(int jy, int jm, int jd, int hour, int minute) {
  final (gy, gm, gd) = jalaliToGregorian(jy, jm, jd);
  return DateTime.utc(gy, gm, gd, hour, minute).subtract(kTehranOffset);
}

String _two(int v) => v.toString().padLeft(2, '0');
String faDigits(String s) {
  const d = '۰۱۲۳۴۵۶۷۸۹';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => d[int.parse(m[0]!)]);
}

/// e.g. «شنبه ۲۴ آبان ۱۴۰۵ · ۱۸:۳۰» (Tehran time)
String jalaliLabel(DateTime utc, {bool year = false, bool weekday = true, bool time = true}) {
  final w = tehranWall(utc);
  final (jy, jm, jd) = gregorianToJalali(w.year, w.month, w.day);
  final parts = <String>[
    if (weekday) kFaWeekdays[w.weekday]!,
    '$jd ${kJalaliMonths[jm - 1]}${year ? ' $jy' : ''}',
  ];
  final s = parts.join(' ') + (time ? ' · ${_two(w.hour)}:${_two(w.minute)}' : '');
  return faDigits(s);
}

String tehranClock(DateTime utc) {
  final w = tehranWall(utc);
  return faDigits('${_two(w.hour)}:${_two(w.minute)}');
}

/// «۲ ساعت و ۵ دقیقه» / «۴۵ ثانیه»
String faCountdown(Duration d) {
  if (d.isNegative) return faDigits('0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (d.inDays >= 1) return faDigits('${d.inDays} روز و ${h % 24} ساعت');
  if (h > 0) return faDigits('$h ساعت و $m دقیقه');
  if (m > 0) return faDigits('$m دقیقه و $s ثانیه');
  return faDigits('$s ثانیه');
}
