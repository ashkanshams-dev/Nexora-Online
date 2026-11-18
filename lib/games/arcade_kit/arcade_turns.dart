import 'dart:async';

import '../core/net_link.dart';

/// Ordered move log for the turn-based arcade games (pool, golf, chess, ludo battle, spy & mafia).
///
/// Every phone runs the same pure-Dart core with the same seed and applies the same moves in the same order:
///  * [send] posts this phone's move (the caller applies it locally right away);
///  * [onMove] receives every other move in order; after a (re)join the whole history is replayed first with
///    [NetMove.replay] = true (apply instantly, no animation), then [onReplayDone] fires.
///  * 'forfeit' moves (a player left) and 'timeout' moves (the authority skipped an absent player) arrive through
///    [onMove] like any other move.
class ArcadeTurnNet {
  ArcadeTurnNet(this.net, {required this.onMove, this.onReplayDone});
  final NetLink net;
  final Future<void> Function(NetMove move) onMove;
  final void Function()? onReplayDone;
  NetInbox? _inbox;
  bool replaying = true;

  int get mySeat => net.mySeat;
  bool get isAuthority => net.isAuthority;

  void start() {
    final NetInbox inbox = NetInbox(_handle);
    _inbox = inbox;
    net.listen(inbox.add,
        onReplayDone: () => inbox.add(const NetMove(seq: -1, seat: -1, kind: 'replayDone', data: <String, dynamic>{})));
  }

  Future<void> _handle(NetMove m) async {
    if (m.kind == 'replayDone') {
      replaying = false;
      onReplayDone?.call();
      return;
    }
    await onMove(m);
  }

  /// Whose turn it is (lets the authority time out absent players).
  set turn(int? seat) => net.turnSeat = seat;

  Future<bool> send(Map<String, dynamic> data, {int? asSeat}) => net.send(data, asSeat: asSeat);

  void dispose() => _inbox?.close();
}
