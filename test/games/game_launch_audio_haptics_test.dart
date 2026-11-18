import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/core/game_contract.dart';

GameLaunch _launch({required bool soundOn, required bool hapticsOn}) =>
    GameLaunch(
      gameId: 'contract-test',
      mode: GameMode.local,
      difficulty: BotDifficulty.normal,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: soundOn,
      hapticsOn: hapticsOn,
      onFinish: (_) {},
    );

void main() {
  test('sound and haptics can both be enabled', () {
    final GameLaunch launch = _launch(soundOn: true, hapticsOn: true);
    expect(launch.soundOn, isTrue);
    expect(launch.hapticsOn, isTrue);
  });

  test('sound can be enabled while haptics are disabled', () {
    final GameLaunch launch = _launch(soundOn: true, hapticsOn: false);
    expect(launch.soundOn, isTrue);
    expect(launch.hapticsOn, isFalse);
  });

  test('haptics can be enabled while sound is disabled', () {
    final GameLaunch launch = _launch(soundOn: false, hapticsOn: true);
    expect(launch.soundOn, isFalse);
    expect(launch.hapticsOn, isTrue);
  });

  test('both channels can be disabled', () {
    final GameLaunch launch = _launch(soundOn: false, hapticsOn: false);
    expect(launch.soundOn, isFalse);
    expect(launch.hapticsOn, isFalse);
  });

  test('haptics stays enabled for callers using the legacy constructor shape', () {
    final GameLaunch launch = GameLaunch(
      gameId: 'legacy-contract-test',
      mode: GameMode.local,
      difficulty: BotDifficulty.normal,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      onFinish: (_) {},
    );
    expect(launch.hapticsOn, isTrue);
  });
}
