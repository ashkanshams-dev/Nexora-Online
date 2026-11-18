import '../core/game_contract.dart';

String ordinalEn(int n) => n == 1 ? '1st' : n == 2 ? '2nd' : n == 3 ? '3rd' : '${n}th';
String ordinalFa(int n) => const <String>['', 'اول', 'دوم', 'سوم', 'چهارم', 'پنجم', 'ششم', 'هفتم', 'هشتم'][n.clamp(1, 8)];

/// Result of a ranked multiplayer round from this phone's point of view.
/// [order] lists seats best → worst. Seat points = players − rank (winner gets the most).
GameResult rankedResult(GameLaunch l, List<int> order, {String whatFa = '', String whatEn = ''}) {
  final int n = order.length;
  final int me = l.mySeat;
  final int place = order.indexOf(me) + 1;
  final List<int> scores = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    if (order[i] >= 0 && order[i] < n) scores[order[i]] = n - i;
  }
  final int myPts = place > 0 ? n - place + 1 : 0;
  final int bestOther = n > 1 ? (place == 1 ? n - 1 : n) : 0;
  return GameResult(
    outcome: place == 1 ? GameOutcome.win : GameOutcome.loss,
    score: myPts,
    opponentScore: bestOther,
    winnerSeats: <int>[order.first],
    scores: scores,
    summaryFa: '${whatFa.isEmpty ? '' : '$whatFa · '}نفر ${ordinalFa(place)} از $n',
    summaryEn: '${whatEn.isEmpty ? '' : '$whatEn · '}${ordinalEn(place)} of $n',
    tournamentMatchId: l.tournamentMatchId,
  );
}

/// Bot skill per difficulty (0..1).
double botSkillFor(BotDifficulty d) => switch (d) {
      BotDifficulty.easy => 0.3,
      BotDifficulty.normal => 0.62,
      BotDifficulty.hard => 0.92,
    };
