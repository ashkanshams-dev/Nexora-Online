// FastLink — port of src/net/fastlink.ts: low-latency game transport over LiveKit WebRTC data channels
// (separate data-only LiveKit room "nexora-<room>-g" minted by the same `livekit-token` function with purpose:'game').
// Supabase Realtime broadcast stays as the duplicate/fallback path; RoomLink de-duplicates by (from, mid).
import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'supabase.dart';
import 'voice.dart';

class FastLink {
  final String roomId;
  final void Function(Map<String, dynamic> m) onMsg;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _ev;
  bool _alive = true, ready = false;
  Timer? _retry;
  int _tries = 0;

  FastLink(this.roomId, this.onMsg) {
    _start();
  }

  Future<void> _start() async {
    if (!_alive) return;
    try {
      if (!voiceSupport().ok) return;
      final r = await supabase.functions.invoke('livekit-token', body: {'room_id': roomId, 'purpose': 'game'});
      final data = r.data is Map ? r.data as Map : null;
      if (data?['token'] == null || !_alive) throw Exception('token');
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false));
      _ev = room.createListener()
        ..on<lk.DataReceivedEvent>((e) {
          if (e.topic != null && e.topic != 'g') return;
          try {
            onMsg(Map<String, dynamic>.from(jsonDecode(utf8.decode(e.data)) as Map));
          } catch (_) {}
        })
        ..on<lk.RoomDisconnectedEvent>((_) {
          ready = false;
          if (_alive) _again();
        });
      await room.connect(data!['url'] as String, data['token'] as String, connectOptions: const lk.ConnectOptions(autoSubscribe: false));
      if (!_alive) {
        await room.disconnect();
        return;
      }
      _room = room;
      ready = true;
      _tries = 0;
    } catch (_) {
      ready = false;
      _again();
    }
  }

  void _again() {
    if (!_alive || _tries > 4) return;
    _tries++;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: 1500 * _tries), _start);
  }

  /// true when the packet was handed to WebRTC
  bool send(Map<String, dynamic> m, [bool reliable = true]) {
    final r = _room;
    if (!ready || r == null) return false;
    try {
      r.localParticipant?.publishData(utf8.encode(jsonEncode(m)), reliable: reliable, topic: 'g');
      return true;
    } catch (_) {
      return false;
    }
  }

  void destroy() {
    _alive = false;
    ready = false;
    _retry?.cancel();
    _ev?.dispose();
    try {
      _room?.disconnect();
    } catch (_) {}
    _room = null;
  }
}
