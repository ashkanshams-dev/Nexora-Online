import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/arcade/online/matchmaking_state.dart';

void main() {
  test('search, reconnect and resume preserve one attempt', () {
    const MatchmakingState initial = MatchmakingState();
    final MatchmakingState searching = initial.start();
    expect(searching.phase, MatchmakingPhase.searching);
    expect(searching.attempt, 1);

    final MatchmakingState reconnecting = searching.reconnecting();
    expect(reconnecting.phase, MatchmakingPhase.reconnecting);
    expect(reconnecting.active, isTrue);
    expect(reconnecting.attempt, 1);

    final MatchmakingState resumed = reconnecting.resumeSearching();
    expect(resumed.phase, MatchmakingPhase.searching);
    expect(resumed.attempt, 1);
  });

  test('timeout and cancel are terminal until a new retry', () {
    final MatchmakingState searching = const MatchmakingState().start();
    final MatchmakingState timedOut = searching.timeout();
    expect(timedOut.phase, MatchmakingPhase.timedOut);
    expect(timedOut.active, isFalse);
    expect(timedOut.retryable, isTrue);

    final MatchmakingState retry = timedOut.start();
    expect(retry.phase, MatchmakingPhase.searching);
    expect(retry.attempt, 2);

    final MatchmakingState cancelled = retry.cancel();
    expect(cancelled.phase, MatchmakingPhase.cancelled);
    expect(cancelled.retryable, isTrue);
  });

  test('matched stores room identity and is no longer active', () {
    final MatchmakingState matched = const MatchmakingState()
        .start()
        .matched('room-42');
    expect(matched.phase, MatchmakingPhase.matched);
    expect(matched.roomId, 'room-42');
    expect(matched.active, isFalse);
  });

  test('failure stores a retryable error without losing attempt', () {
    final MatchmakingState failed = const MatchmakingState()
        .start()
        .fail('network unavailable');
    expect(failed.phase, MatchmakingPhase.failed);
    expect(failed.error, 'network unavailable');
    expect(failed.attempt, 1);
    expect(failed.retryable, isTrue);
  });
}
