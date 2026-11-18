import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/online_service.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';

/// Shows admin announcements (`nx_announcements`, Realtime + catch-up on start) once per device.
class AnnouncementWatcher {
  AnnouncementWatcher(this._ref, this._messenger);
  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messenger;
  RealtimeChannel? _ch;
  String? _uid;
  static const String _kSeen = 'nx_announcements_seen';

  Set<int> get _seen => (LocalStore.instance.prefs.getStringList(_kSeen) ?? const <String>[])
      .map((String e) => int.tryParse(e) ?? -1)
      .toSet();

  void _markSeen(int id) {
    final List<String> l = (LocalStore.instance.prefs.getStringList(_kSeen) ?? <String>[])..add('$id');
    unawaited(LocalStore.instance.prefs.setStringList(_kSeen, l.length > 200 ? l.sublist(l.length - 200) : l));
  }

  void sync() {
    final OnlineService o = _ref.read(onlineProvider);
    final String? uid = o.isOnline ? o.uid : null;
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    final SupabaseClient? c = o.client;
    if (uid == null || c == null) return;
    _ch = c
        .channel('nxann:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_announcements',
          callback: (PostgresChangePayload p) => _show(p.newRecord),
        )
        .subscribe();
    unawaited(_catchUp(c));
  }

  Future<void> _catchUp(SupabaseClient c) async {
    try {
      final List<dynamic> rows = await c.from('nx_announcements').select().order('created_at', ascending: false).limit(3);
      for (final dynamic r in rows.reversed) {
        _show(Map<String, dynamic>.from(r as Map));
      }
    } catch (_) {}
  }

  void _show(Map<String, dynamic> r) {
    final int id = (r['id'] as num?)?.toInt() ?? -1;
    if (id < 0 || _seen.contains(id) || r['active'] == false) return;
    final ScaffoldMessengerState? m = _messenger.currentState;
    if (m == null) return;
    _markSeen(id);
    m.showMaterialBanner(MaterialBanner(
      backgroundColor: NxColors.navySoft,
      leading: const Icon(Icons.campaign_rounded, color: NxColors.gold),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('${r['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, color: NxColors.iceWhite)),
        if ('${r['body'] ?? ''}'.isNotEmpty)
          Text('${r['body']}', style: const TextStyle(color: NxColors.textDim)),
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => m.hideCurrentMaterialBanner(), child: const Text('OK')),
      ],
    ));
  }

  void _detach({bool disposing = false}) {
    final RealtimeChannel? ch = _ch;
    _ch = null;
    if (ch == null) return;
    // On dispose the app's `ref` is already unusable (Riverpod throws), so only unsubscribe the channel itself.
    if (disposing) {
      unawaited(ch.unsubscribe());
      return;
    }
    final SupabaseClient? c = _ref.read(onlineProvider).client;
    if (c != null) unawaited(c.removeChannel(ch));
  }

  void dispose() => _detach(disposing: true);
}
