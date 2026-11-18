/// Pure-Dart state machine for a quick-match client session.
///
/// Server RPCs remain authoritative; this model only prevents stale UI actions
/// and makes timeout/cancel/retry/reconnect transitions deterministic.
enum MatchmakingPhase {
  idle,
  searching,
  reconnecting,
  matched,
  cancelled,
  timedOut,
  failed,
}

class MatchmakingState {
  const MatchmakingState({
    this.phase = MatchmakingPhase.idle,
    this.attempt = 0,
    this.roomId,
    this.error,
  });

  final MatchmakingPhase phase;
  final int attempt;
  final String? roomId;
  final String? error;

  bool get active => phase == MatchmakingPhase.searching || phase == MatchmakingPhase.reconnecting;
  bool get retryable => phase == MatchmakingPhase.cancelled || phase == MatchmakingPhase.timedOut || phase == MatchmakingPhase.failed;

  MatchmakingState start() => MatchmakingState(
        phase: MatchmakingPhase.searching,
        attempt: attempt + 1,
      );

  MatchmakingState resumeSearching() => MatchmakingState(
        phase: MatchmakingPhase.searching,
        attempt: attempt,
      );

  MatchmakingState reconnecting() => MatchmakingState(
        phase: MatchmakingPhase.reconnecting,
        attempt: attempt,
      );

  MatchmakingState matched(String id) => MatchmakingState(
        phase: MatchmakingPhase.matched,
        attempt: attempt,
        roomId: id,
      );

  MatchmakingState cancel() => MatchmakingState(
        phase: MatchmakingPhase.cancelled,
        attempt: attempt,
      );

  MatchmakingState timeout() => MatchmakingState(
        phase: MatchmakingPhase.timedOut,
        attempt: attempt,
      );

  MatchmakingState fail(String message) => MatchmakingState(
        phase: MatchmakingPhase.failed,
        attempt: attempt,
        error: message,
      );
}
