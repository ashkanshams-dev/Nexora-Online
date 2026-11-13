// Realtime matchmaking client for supabase/matchmaking_v2.sql.
//  enqueue (mode, kind, region, RTT) → Realtime postgres_changes on my mm_tickets row + mm_poll() keep-alive every 2 s
//  (the poll also runs the server matcher, so two clients alone still match without any cron) → 'matched' carries the
//  room id; the room is already started server-side, so the lobby jumps straight into the match.
//  Bot fill happens server-side after bot_after seconds. Cancel / timeout / network loss are handled here.
//  If the v2 RPCs are not deployed, falls back to the classic quick_match room join.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../net/supabase.dart';
import '../sound.dart';

enum MMStatus { idle, searching, matched, failed }

class MMState {
  final MMStatus status;
  final String? mode, kind, error;
  final int startedAt, queued, rtt;
  final JRow? room;
  final bool bots;
  const MMState({this.status = MMStatus.idle, this.mode, this.kind, this.error, this.startedAt = 0, this.queued = 0, this.rtt = 0, this.room, this.bots = false});
  int get waited => startedAt == 0 ? 0 : ((DateTime.now().millisecondsSinceEpoch - startedAt) / 1000).floor();
}

/// coarse region bucket from the device UTC offset (+ language), used to prefer close opponents first
String deviceRegion() {
  final off = DateTime.now().timeZoneOffset.inMinutes;
  final b = off >= 150 && off <= 300 ? 'me' : off >= -60 && off < 150 ? 'eu' : off > 300 && off <= 600 ? 'as' : off > 600 ? 'oc' : 'am';
  return '$b${(off / 60).round()}';
}

class Matchmaker extends ValueNotifier<MMState> {
  Matchmaker._() : super(const MMState());
  static final Matchmaker I = Matchmaker._();

  RealtimeChannel? _ch;
  Timer? _poll;
  int _rtt = 0;
  bool _busy = false;
  void Function(JRow room)? onMatched;
  /// a room joined from outside the online area (invite / notification) → OnlineRoot enters it on open
  JRow? pendingRoom;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> start(String mode, {String kind = 'quick', int botAfter = 25}) async {
    if (value.status == MMStatus.searching) await cancel();
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      value = const MMState(status: MMStatus.failed, error: 'اول وارد حساب شو');
      return;
    }
    value = MMState(status: MMStatus.searching, mode: mode, kind: kind, startedAt: _now());
    sfx(Sfx.ready);
    _listen(uid);
    try {
      final t0 = _now();
      final t = await supabase.rpc('mm_enqueue', params: {'p_mode': mode, 'p_kind': kind, 'p_region': deviceRegion(), 'p_rtt': _rtt == 0 ? null : _rtt, 'p_bot_after': botAfter});
      _rtt = _now() - t0;
      await _ticket(t is Map ? Map<String, dynamic>.from(t) : null);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
      _stats();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.message.contains('mm_enqueue')) {
        // v2 not deployed → classic room-based quick match
        await _stop();
        try {
          final r = await rpc('quick_match', {'p_mode': mode, 'p_kind': kind});
          value = MMState(status: MMStatus.matched, mode: mode, kind: kind, room: Map<String, dynamic>.from(r as Map));
          onMatched?.call(value.room!);
        } catch (e2) {
          value = MMState(status: MMStatus.failed, error: errFa(e2));
        }
      } else {
        await _stop();
        value = MMState(status: MMStatus.failed, error: errFa(e));
      }
    } catch (e) {
      await _stop();
      value = MMState(status: MMStatus.failed, error: errFa(e));
    }
  }

  void _listen(String uid) {
    _ch?.unsubscribe();
    _ch = supabase
        .channel('mm:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mm_tickets',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) => _ticket(p.newRecord.isEmpty ? null : p.newRecord),
        )
        .subscribe();
  }

  Future<void> _tick() async {
    if (_busy || value.status != MMStatus.searching) return;
    _busy = true;
    try {
      final t0 = _now();
      final t = await supabase.rpc('mm_poll', params: {'p_rtt': _rtt == 0 ? null : _rtt});
      final d = _now() - t0;
      _rtt = _rtt == 0 ? d : (_rtt * .7 + d * .3).round();
      await _ticket(t is Map ? Map<String, dynamic>.from(t) : null);
      if (value.waited % 6 == 0) _stats();
    } catch (_) {
      // transient network loss: keep the ticket; the server expires it after 12 s without a poll
      if (value.waited > 130) {
        await _stop();
        value = MMState(status: MMStatus.failed, mode: value.mode, kind: value.kind, error: 'اتصال قطع شد؛ دوباره جستجو کن');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _stats() async {
    try {
      final rows = await supabase.rpc('mm_stats');
      final n = (rows as List).cast<Map>().where((r) => r['mode'] == value.mode && r['kind'] == value.kind).map((r) => (r['searching'] as num).toInt()).fold(0, (a, b) => a + b);
      if (value.status == MMStatus.searching) {
        value = MMState(status: value.status, mode: value.mode, kind: value.kind, startedAt: value.startedAt, queued: n, rtt: _rtt);
      }
    } catch (_) {}
  }

  Future<void> _ticket(JRow? t) async {
    if (t == null || value.status != MMStatus.searching) return;
    final st = t['status'];
    if (st == 'matched' && t['room_id'] != null) {
      final rid = t['room_id'] as String;
      await _stop();
      try {
        final room = await supabase.from('rooms').select().eq('id', rid).maybeSingle();
        if (room == null) throw 'room not found';
        value = MMState(status: MMStatus.matched, mode: value.mode, kind: value.kind, room: room, bots: t['bots'] == true);
        sfx(Sfx.join);
        buzz(Buzz.success);
        onMatched?.call(room);
      } catch (e) {
        value = MMState(status: MMStatus.failed, error: errFa(e));
      }
    } else if (st == 'expired' || st == 'cancelled') {
      await _stop();
      value = st == 'expired' ? const MMState(status: MMStatus.failed, error: 'حریفی پیدا نشد؛ دوباره امتحان کن') : const MMState();
    }
  }

  Future<void> _stop() async {
    _poll?.cancel();
    _poll = null;
    final c = _ch;
    _ch = null;
    if (c != null) await supabase.removeChannel(c).catchError((_) => 'error');
  }

  Future<void> cancel() async {
    final was = value.status == MMStatus.searching;
    await _stop();
    value = const MMState();
    if (was) await supabase.rpc('mm_cancel').catchError((_) => null);
  }

  void reset() {
    if (value.status != MMStatus.searching) value = const MMState();
  }
}
