import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/spy_mafia/core/spy_core.dart';

void main() {
  test('roles: one spy up to 6 players, two from 7', () {
    expect(SpyGame(players: 5, seed: 1).spies.length, 1);
    expect(SpyGame(players: 8, seed: 1).spies.length, 2);
  });

  test('agents get location words, spies never do', () {
    for (int seed = 0; seed < 20; seed++) {
      final SpyGame g = SpyGame(players: 6, seed: seed);
      for (int s = 0; s < 6; s++) {
        final List<int> o = g.options(s);
        expect(o.length, 3);
        expect(o.every((int w) => (spyWordLoc(w) == g.location) != g.isSpy(s)), isTrue);
      }
    }
  });

  test('clue rounds go round the table twice then voting starts', () {
    final SpyGame g = SpyGame(players: 4, seed: 3);
    final int first = g.turn;
    expect(g.giveClue((first + 1) % 4, 0), isFalse, reason: 'not your turn');
    for (int i = 0; i < 8; i++) {
      expect(g.giveClue(g.turn, i % 3), isTrue);
    }
    expect(g.phase, SpyPhase.vote);
    expect(g.clues.every((List<int> c) => c.length == 2), isTrue);
  });

  test('voting out the spy leads to the guess; a right guess steals the win', () {
    final SpyGame g = SpyGame(players: 4, seed: 7);
    for (int i = 0; i < 8; i++) {
      g.giveClue(g.turn, 0);
    }
    final int spy = g.spies.first;
    for (int s = 0; s < 4; s++) {
      g.vote(s, s == spy ? (spy + 1) % 4 : spy);
    }
    expect(g.phase, SpyPhase.guess);
    expect(g.accused, spy);
    expect(g.guessOptions(), contains(g.location));
    g.guess(g.location);
    expect(g.spiesWin, isTrue);
    expect(g.ranking().first, spy);
  });

  test('a tie protects the spy; bots play complete games', () {
    final SpyGame g = SpyGame(players: 4, seed: 2);
    for (int i = 0; i < 8; i++) {
      g.giveClue(g.turn, 1);
    }
    g.vote(0, 1);
    g.vote(1, 0);
    g.vote(2, 3);
    g.vote(3, 2);
    expect(g.over, isTrue);
    expect(g.spiesWin, isTrue);
    final math.Random r = math.Random(1);
    int agentWins = 0;
    for (int seed = 0; seed < 40; seed++) {
      final SpyGame b = SpyGame(players: 6, seed: seed);
      while (b.phase == SpyPhase.clues) {
        b.giveClue(b.turn, b.botClue(b.turn, r));
      }
      for (int s = 0; s < 6; s++) {
        b.vote(s, b.botVote(s, r, 0.92));
      }
      if (b.phase == SpyPhase.guess) b.guess(b.botGuess(r, 0.3));
      expect(b.over, isTrue);
      if (!b.spiesWin) agentWins++;
    }
    expect(agentWins, greaterThan(5), reason: 'smart agents catch spies sometimes');
    expect(agentWins, lessThan(40));
  });

  test('a leaving lone spy ends the game for the agents', () {
    final SpyGame g = SpyGame(players: 5, seed: 4);
    g.leave(g.spies.first);
    expect(g.over, isTrue);
    expect(g.spiesWin, isFalse);
  });
}
