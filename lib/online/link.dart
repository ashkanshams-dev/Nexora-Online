// RoomLink — port of src/online/link.ts. One realtime connection per joined room, shared by lobby + match:
//  - postgres_changes on rooms / room_players → refetch room state (debounced)
//  - broadcast 'chat' / 'sync' / 'pi'+'po' (RTT probe) / 'g' (match netcode)
//  - presence (key = user id) → who is connected right now
//  - every game packet is sent on BOTH paths (LiveKit data channel + Supabase broadcast) with a per-sender id;
//    whichever arrives first wins and the copy is dropped. Wire format is byte-compatible with the RN client.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../net/fastlink.dart';
import '../net/supabase.dart';
import '../net/voice.dart';
import '../sound.dart';

class ChatMsg {
  final String id, uid, name, text;
  final int ts;
  const ChatMsg(this.id, this.uid, this.name, this.text, this.ts);
  Map<String, dynamic> toJson() => {'id': id, 'uid': uid, 'name': name, 'text': text, 'ts': ts};
  static ChatMsg? from(Map<String, dynamic>? m) {
    if (m == null || m['text'] is! String) return null;
    final t = m['text'] as String;
    return ChatMsg('${m['id']}', '${m['uid']}', '${m['name'] ?? ''}', t.substring(0, math.min(200, t.length)), (m['ts'] as num?)?.toInt() ?? 0);
  }
}

class LinkState {
  final JRow? room;
  final List<JRow> players;
  final Map<String, String> online; // uid → name
  final List<ChatMsg> chat;
  final bool connected, loaded, gone;
  final int unread;
  final int? rtt;
  const LinkState({this.room, this.players = const [], this.online = const {}, this.chat = const [], this.connected = false, this.loaded = false, this.gone = false, this.unread = 0, this.rtt});
  LinkState copy({JRow? room, List<JRow>? players, Map<String, String>? online, List<ChatMsg>? chat, bool? connected, bool? loaded, bool? gone, int? unread, int? rtt, bool clearRtt = false}) => LinkState(
      room: room ?? this.room, players: players ?? this.players, online: online ?? this.online, chat: chat ?? this.chat, connected: connected ?? this.connected,
      loaded: loaded ?? this.loaded, gone: gone ?? this.gone, unread: unread ?? this.unread, rtt: clearRtt ? null : rtt ?? this.rtt);
}

typedef GameListener = void Function(Map<String, dynamic> m, String? from);

class RoomLink extends ValueNotifier<LinkState> {
  final String id, me;
  String myName;
  RealtimeChannel? _ch;
  final Set<GameListener> _gl = {};
  Timer? _t, _poll, _beat, _pinger;
  bool _dead = false, chatOpen = false;
  final Set<String> _seenOnline = {};
  late final Voice voice = Voice(id);
  FastLink? _fast;
  int _mid = 0;
  final Map<String, int> _seen = {};

  RoomLink(this.id, this.me, this.myName) : super(const LinkState()) {
    _connect();
    _fast = FastLink(id, _gotGame);
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
    _heartbeat();
    _pinger = Timer.periodic(const Duration(seconds: 3), (_) => _probe());
  }

  void _heartbeat() => supabase.rpc('heartbeat', params: {'p_room': id}).then((_) {}, onError: (_) {});
  static int _now() => DateTime.now().millisecondsSinceEpoch;
  void _set(LinkState s) {
    if (!_dead) value = s;
  }

  void _probe() {
    final ch = _ch;
    if (ch == null || !value.connected) return;
    final host = value.room?['host'] as String?;
    final to = host != null && host != me && value.online.containsKey(host) ? host : value.online.keys.where((k) => k != me).firstOrNull;
    if (to == null) {
      if (value.rtt != null) _set(value.copy(clearRtt: true));
      return;
    }
    if (_fast?.ready == true) {
      _fast!.send({'k': '_pi', 't': _now(), 'from': me, 'to': to}, false);
      return;
    }
    ch.sendBroadcastMessage(event: 'pi', payload: {'t': _now(), 'f': me, 'to': to}).catchError((_) => ChannelResponse.error);
  }

  void _rtt(int t) {
    final r = math.max(1, _now() - t);
    if (r > 10000) return;
    final prev = value.rtt;
    _set(value.copy(rtt: (prev == null ? r : prev * .6 + r * .4).round()));
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> p) => p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : p;

  void _connect() {
    final ch = supabase.channel('room:$id', opts: RealtimeChannelConfig(self: false, ack: false, key: me, enabled: true));
    ch
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'rooms', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id), callback: (_) => _soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: id), callback: (_) => _soon())
        .onBroadcast(event: 'sync', callback: (_) => _soon())
        .onBroadcast(event: 'chat', callback: (p) => _addChat(ChatMsg.from(_unwrap(p))))
        .onBroadcast(event: 'pi', callback: (p) {
          final m = _unwrap(p);
          if (m['to'] == me) ch.sendBroadcastMessage(event: 'po', payload: {'t': m['t'], 'to': m['f']}).catchError((_) => ChannelResponse.error);
        })
        .onBroadcast(event: 'po', callback: (p) {
          final m = _unwrap(p);
          if (m['to'] == me && m['t'] is num) _rtt((m['t'] as num).toInt());
        })
        .onBroadcast(event: 'g', callback: (p) => _gotGame(_unwrap(p)))
        .onPresenceSync((_) {
          final online = <String, String>{};
          for (final s in ch.presenceState()) {
            online[s.key] = s.presences.isNotEmpty ? '${s.presences.first.payload['name'] ?? ''}' : '';
          }
          for (final k in online.keys) {
            if (_seenOnline.add(k) && k != me && value.connected) sfx(Sfx.join);
          }
          for (final k in _seenOnline.toList()) {
            if (!online.containsKey(k)) {
              _seenOnline.remove(k);
              if (k != me) sfx(Sfx.leave);
            }
          }
          _set(value.copy(online: online));
          _soon();
        })
        .subscribe((st, _) async {
          if (_dead) return;
          if (st == RealtimeSubscribeStatus.subscribed) {
            _set(value.copy(connected: true));
            try {
              await ch.track({'name': myName});
            } catch (_) {}
            refresh();
          } else if (st == RealtimeSubscribeStatus.channelError || st == RealtimeSubscribeStatus.timedOut || st == RealtimeSubscribeStatus.closed) {
            _set(value.copy(connected: false));
          }
        });
    _ch = ch;
  }

  void _soon() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 150), refresh);
  }

  Future<void> refresh() async {
    if (_dead) return;
    try {
      final res = await Future.wait([
        supabase.from('rooms').select().eq('id', id).maybeSingle(),
        supabase.from('room_players').select('*, profiles(username, avatar, avatar_url, level, rating, league, equipped_disc)').eq('room_id', id).order('joined_at'),
      ]);
      if (_dead) return;
      final r = res[0] as JRow?, players = (res[1] as List).cast<JRow>();
      final gone = r == null || !players.any((x) => x['user_id'] == me);
      _set(value.copy(room: r ?? value.room, players: players, loaded: true, gone: gone));
    } catch (_) {}
  }

  void ping() => _ch?.sendBroadcastMessage(event: 'sync', payload: {}).catchError((_) => ChannelResponse.error);

  void _addChat(ChatMsg? c) {
    if (c == null) return;
    final chat = [...value.chat, c];
    if (chat.length > 80) chat.removeRange(0, chat.length - 80);
    if (c.uid != me) sfx(Sfx.chat);
    _set(value.copy(chat: chat, unread: chatOpen || c.uid == me ? 0 : value.unread + 1));
  }

  void sendChat(String text) {
    var t = text.trim();
    if (t.isEmpty) return;
    if (t.length > 200) t = t.substring(0, 200);
    final c = ChatMsg('${_now()}-${math.Random().nextInt(1 << 30).toRadixString(36)}', me, myName, t, _now());
    _addChat(c);
    _ch?.sendBroadcastMessage(event: 'chat', payload: c.toJson()).catchError((_) => ChannelResponse.error);
  }

  void markRead() {
    if (value.unread > 0) _set(value.copy(unread: 0));
  }

  VoidCallback onGame(GameListener f) {
    _gl.add(f);
    return () => _gl.remove(f);
  }

  /// every game packet goes out on BOTH paths with a per-sender id; first arrival wins
  void sendGame(Map<String, dynamic> m) {
    final p = {...m, 'from': me, 'mid': ++_mid};
    _fast?.send(p, true);
    _ch?.sendBroadcastMessage(event: 'g', payload: p).catchError((_) => ChannelResponse.error);
  }

  bool get fastReady => _fast?.ready == true;

  void _gotGame(Map<String, dynamic> m) {
    final from = m['from'] as String?;
    if (from == me) return;
    final k = m['k'];
    if (k == '_pi') {
      if (m['to'] == me) _fast?.send({'k': '_po', 't': m['t'], 'from': me, 'to': from}, false);
      return;
    }
    if (k == '_po') {
      if (m['to'] == me && m['t'] is num) _rtt((m['t'] as num).toInt());
      return;
    }
    final mid = m['mid'];
    if (mid is num) {
      final key = '$from:${mid.toInt()}';
      if (_seen.containsKey(key)) return;
      _seen[key] = _now();
      if (_seen.length > 600) {
        final cut = _now() - 20000;
        _seen.removeWhere((_, t) => t < cut);
        if (_seen.length > 600) _seen.clear();
      }
    }
    for (final f in _gl.toList()) {
      f(m, from);
    }
  }

  void destroy() {
    _dead = true;
    _t?.cancel();
    _poll?.cancel();
    _beat?.cancel();
    _pinger?.cancel();
    voice.destroy();
    _fast?.destroy();
    _fast = null;
    final c = _ch;
    _ch = null;
    if (c != null) {
      c.untrack().whenComplete(() => supabase.removeChannel(c)).catchError((_) => ChannelResponse.error);
    }
    _gl.clear();
  }
}
