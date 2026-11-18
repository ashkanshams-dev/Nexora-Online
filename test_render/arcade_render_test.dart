import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/arcade_registry.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arcade_util.dart';

GameLaunch launch(String id, {int players = 4}) => GameLaunch(
      gameId: id, mode: GameMode.vsBot, difficulty: BotDifficulty.normal, playerName: 'Ashkan',
      isFa: false, fancyEffects: true, reducedMotion: false, soundOn: false, seed: 2, playerCount: players, onFinish: (_) {});

const String only = String.fromEnvironment('ONLY');
const int secs = int.fromEnvironment('SECS', defaultValue: 5);
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
    await loadFonts();
  });
  for (final GameInfo g in kArcadeGames) {
    if (only.isNotEmpty && !only.split(',').contains(g.id)) continue;
    testWidgets('render ${g.id}', (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(shotApp(g.builder(launch(g.id, players: g.defaultPlayers))));
      for (int i = 0; i < secs * 30; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      await shoot(tester, 'arcade/${g.id}.png');
      // tap the middle (starts solo runs) and play a little more
      await tester.tapAt(const Offset(195, 600));
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      await shoot(tester, 'arcade/${g.id}_b.png');
    });
  }
}
