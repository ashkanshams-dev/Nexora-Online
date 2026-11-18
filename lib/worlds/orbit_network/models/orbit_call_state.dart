/// Connection state used by the LiveKit call UI.
///
/// This deliberately contains no Flutter or LiveKit types so reconnect and
/// retry behavior can be tested deterministically in the unit-test suite.
enum OrbitCallConnection {
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}

class OrbitCallState {
  const OrbitCallState({
    this.connection = OrbitCallConnection.connecting,
    this.reconnectCount = 0,
    this.hadPeer = false,
  });

  final OrbitCallConnection connection;
  final int reconnectCount;
  final bool hadPeer;

  OrbitCallState connected() => OrbitCallState(
        connection: OrbitCallConnection.connected,
        reconnectCount: reconnectCount,
        hadPeer: hadPeer,
      );

  OrbitCallState reconnecting() => OrbitCallState(
        connection: OrbitCallConnection.reconnecting,
        reconnectCount: reconnectCount + 1,
        hadPeer: hadPeer,
      );

  OrbitCallState disconnected() => OrbitCallState(
        connection: OrbitCallConnection.disconnected,
        reconnectCount: reconnectCount,
        hadPeer: hadPeer,
      );

  OrbitCallState failed() => OrbitCallState(
        connection: OrbitCallConnection.failed,
        reconnectCount: reconnectCount,
        hadPeer: hadPeer,
      );

  OrbitCallState withPeer() => OrbitCallState(
        connection: connection,
        reconnectCount: reconnectCount,
        hadPeer: true,
      );
}
