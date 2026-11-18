import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/orbit_network/models/orbit_call_state.dart';

void main() {
  test('reconnect transition increments attempts and returns connected', () {
    const OrbitCallState initial = OrbitCallState();
    final OrbitCallState reconnecting = initial.connected().reconnecting();
    final OrbitCallState restored = reconnecting.connected();

    expect(initial.connection, OrbitCallConnection.connecting);
    expect(reconnecting.connection, OrbitCallConnection.reconnecting);
    expect(reconnecting.reconnectCount, 1);
    expect(restored.connection, OrbitCallConnection.connected);
    expect(restored.reconnectCount, 1);
  });

  test('disconnect and failed states remain retryable without losing peer history', () {
    final OrbitCallState state = const OrbitCallState()
        .connected()
        .withPeer()
        .disconnected();
    final OrbitCallState failed = state.failed();

    expect(state.connection, OrbitCallConnection.disconnected);
    expect(state.hadPeer, isTrue);
    expect(failed.connection, OrbitCallConnection.failed);
    expect(failed.hadPeer, isTrue);
    expect(failed.reconnectCount, 0);
  });
}
