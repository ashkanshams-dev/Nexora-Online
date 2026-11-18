import 'dart:math' as math;

/// NEXORA Spy & Mafia — social deduction for 4-8 players (bots fill empty seats offline).
///
/// Everyone but the SPY sees the secret location (with 7+ players there are two spies, the "mafia").
/// Two clue rounds: on your turn pick one of three clue words. Agents get words that fit the location; spies get
/// words from other places and must bluff. Then everyone votes. If the most-voted player is a spy, the spy may still
/// steal the win by naming the location. Otherwise the spies win. Pure Dart, deterministic for a seed.

class SpyLocation {
  const SpyLocation(this.fa, this.en, this.wordsFa, this.wordsEn);
  final String fa;
  final String en;
  final List<String> wordsFa;
  final List<String> wordsEn;
}

const List<SpyLocation> kSpyLocations = <SpyLocation>[
  SpyLocation('فرودگاه', 'Airport', <String>['چمدان', 'پرواز', 'گذرنامه', 'باند', 'گیت', 'خلبان'],
      <String>['Suitcase', 'Flight', 'Passport', 'Runway', 'Gate', 'Pilot']),
  SpyLocation('بیمارستان', 'Hospital', <String>['پرستار', 'آمبولانس', 'سرم', 'جراحی', 'تخت', 'نسخه'],
      <String>['Nurse', 'Ambulance', 'Drip', 'Surgery', 'Ward bed', 'Prescription']),
  SpyLocation('ساحل', 'Beach', <String>['شن', 'موج', 'چتر', 'کرم ضدآفتاب', 'صدف', 'غریق‌نجات'],
      <String>['Sand', 'Wave', 'Parasol', 'Sunscreen', 'Seashell', 'Lifeguard']),
  SpyLocation('ورزشگاه', 'Stadium', <String>['تماشاگر', 'سوت', 'گل', 'پرچم', 'جایگاه', 'داور'],
      <String>['Crowd', 'Whistle', 'Goal', 'Flag', 'Stands', 'Referee']),
  SpyLocation('مدرسه', 'School', <String>['تخته', 'زنگ تفریح', 'معلم', 'امتحان', 'کیف', 'نیمکت'],
      <String>['Blackboard', 'Recess', 'Teacher', 'Exam', 'Backpack', 'Desk']),
  SpyLocation('رستوران', 'Restaurant', <String>['منو', 'گارسون', 'آشپز', 'انعام', 'رزرو', 'دسر'],
      <String>['Menu', 'Waiter', 'Chef', 'Tip', 'Reservation', 'Dessert']),
  SpyLocation('ایستگاه فضایی', 'Space station', <String>['فضانورد', 'جاذبه', 'ماهواره', 'کپسول', 'مدار', 'لباس فضایی'],
      <String>['Astronaut', 'Gravity', 'Satellite', 'Capsule', 'Orbit', 'Spacesuit']),
  SpyLocation('سینما', 'Cinema', <String>['پاپ‌کورن', 'پرده', 'بلیت', 'ردیف', 'تریلر', 'پروژکتور'],
      <String>['Popcorn', 'Screen', 'Ticket', 'Row', 'Trailer', 'Projector']),
  SpyLocation('بانک', 'Bank', <String>['گاوصندوق', 'وام', 'باجه', 'حساب', 'چک', 'نگهبان'],
      <String>['Vault', 'Loan', 'Teller', 'Account', 'Cheque', 'Guard']),
  SpyLocation('سیرک', 'Circus', <String>['دلقک', 'شعبده', 'چادر', 'بندباز', 'شیر', 'حلقه‌ی آتش'],
      <String>['Clown', 'Magician', 'Big top', 'Tightrope', 'Lion', 'Fire hoop']),
  SpyLocation('زیردریایی', 'Submarine', <String>['پریسکوپ', 'سونار', 'اژدر', 'عمق', 'ناخدا', 'دریچه'],
      <String>['Periscope', 'Sonar', 'Torpedo', 'Depth', 'Captain', 'Hatch']),
  SpyLocation('کافه گیم‌نت', 'Gaming café', <String>['کنسول', 'دسته', 'هدست', 'لگ', 'رنک', 'تورنمنت'],
      <String>['Console', 'Controller', 'Headset', 'Lag', 'Rank', 'Tournament']),
];

/// Clue word reference: location index * 6 + word index.
int spyWord(int loc, int w) => loc * 6 + w;
int spyWordLoc(int ref) => ref ~/ 6;

enum SpyPhase { clues, vote, guess, over }

class SpyGame {
  SpyGame({required this.players, required int seed, this.rounds = 2}) : _seed = seed {
    final math.Random r = math.Random(seed);
    location = r.nextInt(kSpyLocations.length);
    final int spyCount = players >= 7 ? 2 : 1;
    final List<int> seats = List<int>.generate(players, (int i) => i)..shuffle(r);
    spies = seats.take(spyCount).toSet();
    starter = r.nextInt(players);
    turn = starter;
    clues = List<List<int>>.generate(players, (_) => <int>[]);
  }

  final int players;
  final int rounds;
  final int _seed;
  late final int location;
  late final Set<int> spies;
  late final int starter;
  late List<List<int>> clues;
  SpyPhase phase = SpyPhase.clues;
  int turn = 0;
  int round = 0;
  final Map<int, int> votes = <int, int>{}; // voter -> target (-1 = abstain)
  final Set<int> out = <int>{}; // left the match
  int? accused;
  int? guessedLocation;
  bool spiesWin = false;

  bool isSpy(int seat) => spies.contains(seat);
  bool get over => phase == SpyPhase.over;

  /// The three clue options [seat] may choose from this round (deterministic per seat/round).
  List<int> options(int seat, [int? rnd]) {
    final math.Random r = math.Random(_seed * 31 + seat * 977 + (rnd ?? round) * 7919);
    if (!isSpy(seat)) {
      final List<int> w = List<int>.generate(6, (int i) => i)..shuffle(r);
      // never offer a word this seat already used
      final List<int> fresh = w.map((int i) => spyWord(location, i)).where((int x) => !clues[seat].contains(x)).toList();
      return fresh.take(3).toList();
    }
    final List<int> locs = List<int>.generate(kSpyLocations.length, (int i) => i)..remove(location);
    locs.shuffle(r);
    return <int>[for (int k = 0; k < 3; k++) spyWord(locs[k], r.nextInt(6))];
  }

  List<int> get activeSeats => <int>[for (int i = 0; i < players; i++) if (!out.contains(i)) i];

  bool giveClue(int seat, int optionIndex) {
    if (phase != SpyPhase.clues || seat != turn) return false;
    final List<int> o = options(seat);
    if (o.isEmpty) return false;
    clues[seat].add(o[optionIndex.clamp(0, o.length - 1)]);
    _nextTurn();
    return true;
  }

  void _nextTurn() {
    for (int k = 1; k <= players; k++) {
      final int s = (turn + k) % players;
      if (s == starter && k > 0) {
        round++;
        if (round >= rounds) {
          phase = SpyPhase.vote;
          return;
        }
      }
      if (!out.contains(s)) {
        turn = s;
        return;
      }
    }
  }

  bool vote(int voter, int target) {
    if (phase != SpyPhase.vote || votes.containsKey(voter) || out.contains(voter)) return false;
    if (target == voter) return false;
    votes[voter] = target;
    if (activeSeats.every(votes.containsKey)) _tally();
    return true;
  }

  Map<int, int> tally() {
    final Map<int, int> t = <int, int>{};
    for (final int v in votes.values) {
      if (v >= 0) t[v] = (t[v] ?? 0) + 1;
    }
    return t;
  }

  void _tally() {
    final Map<int, int> t = tally();
    int best = -1, bestN = 0;
    bool tie = false;
    t.forEach((int seat, int n) {
      if (n > bestN) {
        best = seat;
        bestN = n;
        tie = false;
      } else if (n == bestN) {
        tie = true;
      }
    });
    accused = (tie || best < 0) ? null : best;
    if (accused != null && isSpy(accused!)) {
      phase = SpyPhase.guess;
    } else {
      spiesWin = true;
      phase = SpyPhase.over;
    }
  }

  /// Six locations shown to the caught spy (always contains the real one), stable for the match.
  List<int> guessOptions() {
    final math.Random r = math.Random(_seed * 13 + 5);
    final List<int> all = List<int>.generate(kSpyLocations.length, (int i) => i)..remove(location);
    all.shuffle(r);
    final List<int> six = <int>[location, ...all.take(5)]..shuffle(r);
    return six;
  }

  bool guess(int loc) {
    if (phase != SpyPhase.guess) return false;
    guessedLocation = loc;
    spiesWin = loc == location;
    phase = SpyPhase.over;
    return true;
  }

  /// A player left: their vote counts as abstain, their clue turn is skipped. A leaving spy ends the round.
  void leave(int seat) {
    if (out.contains(seat) || over) return;
    out.add(seat);
    if (isSpy(seat) && spies.every(out.contains)) {
      spiesWin = false;
      phase = SpyPhase.over;
      return;
    }
    if (phase == SpyPhase.clues && turn == seat) _nextTurn();
    if (phase == SpyPhase.vote && activeSeats.every(votes.containsKey)) _tally();
  }

  // ------------------------------------------------------------------ bots

  /// How suspicious [seat]'s clues look to someone who knows the location (0 = clean).
  int suspicion(int seat) => clues[seat].where((int c) => spyWordLoc(c) != location).length;

  int botClue(int seat, math.Random rng) => rng.nextInt(math.max(1, options(seat).length));

  int botVote(int seat, math.Random rng, double skill) {
    final List<int> cands = <int>[for (final int s in activeSeats) if (s != seat) s];
    if (cands.isEmpty) return -1;
    if (isSpy(seat)) {
      // a spy frames the agent with the oddest-looking clue words, never a fellow spy
      final List<int> agents = cands.where((int s) => !isSpy(s)).toList();
      return agents.isEmpty ? cands.first : agents[rng.nextInt(agents.length)];
    }
    if (rng.nextDouble() > 0.35 + skill * 0.6) return cands[rng.nextInt(cands.length)];
    cands.sort((int a, int b) => suspicion(b) != suspicion(a) ? suspicion(b).compareTo(suspicion(a)) : a.compareTo(b));
    return cands.first;
  }

  /// The caught spy reads everyone's clues and names the best-matching location.
  int botGuess(math.Random rng, double skill) {
    final List<int> opts = guessOptions();
    final Map<int, int> hits = <int, int>{for (final int o in opts) o: 0};
    for (int s = 0; s < players; s++) {
      if (isSpy(s)) continue;
      for (final int c in clues[s]) {
        final int l = spyWordLoc(c);
        if (hits.containsKey(l)) hits[l] = hits[l]! + 1;
      }
    }
    if (rng.nextDouble() > 0.4 + skill * 0.55) return opts[rng.nextInt(opts.length)];
    opts.sort((int a, int b) => hits[b]!.compareTo(hits[a]!));
    return opts.first;
  }

  /// Winners first (lower seat first), then the losing team.
  List<int> ranking() {
    final List<int> win = <int>[], lose = <int>[];
    for (int s = 0; s < players; s++) {
      final bool w = isSpy(s) == spiesWin && !out.contains(s);
      (w ? win : lose).add(s);
    }
    return <int>[...win, ...lose];
  }
}
