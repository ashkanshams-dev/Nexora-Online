// Notifications inbox + live feed: unread count, pending friend requests, realtime inserts → oracle + local alert.
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel;

import '../game/assets.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/notify.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/matchmaker.dart';
import '../online/ui.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'social_feed.dart';

class NotifFeed extends ChangeNotifier {
  NotifFeed._() {
    Auth.I.addListener(_auth);
    _auth();
  }
  static final NotifFeed I = NotifFeed._();

  String? _uid;
  RealtimeChannel? _ch;
  int unread = 0, pendingRequests = 0;
  final List<JRow> recent = [];
  /// set by the chat screen so DMs of the open conversation do not alert
  String? openConversation;

  void _auth() {
    final u = Auth.I.uid;
    if (u == _uid) return;
    _uid = u;
    if (_ch != null) supabase.removeChannel(_ch!);
    _ch = null;
    unread = 0;
    pendingRequests = 0;
    recent.clear();
    notifyListeners();
    if (u == null) return;
    refresh();
    _ch = supabase
        .channel('notif:$u')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert, schema: 'public', table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u),
          callback: (p) => _incoming(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'friend_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'to_user', value: u),
          callback: (_) => refreshRequests(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    final u = _uid;
    if (u == null) return;
    try {
      final d = await supabase.from('notifications').select().eq('user_id', u).order('created_at', ascending: false).limit(60);
      recent
        ..clear()
        ..addAll(List<JRow>.from(d));
      unread = recent.where((n) => n['read'] != true).length;
      notifyListeners();
    } catch (_) {}
    refreshRequests();
  }

  Future<void> refreshRequests() async {
    final u = _uid;
    if (u == null) return;
    try {
      final d = await supabase.from('friend_requests').select('from_user').eq('to_user', u).eq('status', 'pending');
      pendingRequests = (d as List).length;
      notifyListeners();
    } catch (_) {}
  }

  void _incoming(Map<String, dynamic> n) {
    if (n.isEmpty) return;
    recent.insert(0, n);
    if (recent.length > 80) recent.removeLast();
    unread++;
    notifyListeners();
    final kind = n['kind'] as String?, data = (n['data'] as Map?) ?? const {};
    if (kind == 'dm' && data['conversation'] == openConversation) return;
    switch (kind) {
      case 'dm':
        OracleBus.I.react(OracleEvent.message, n['title'] as String?);
      case 'follow' || 'friend_request' || 'friend_accept':
        OracleBus.I.react(OracleEvent.follow, (n['title'] as String?)?.split(' ').first);
      default:
        OracleBus.I.coach(n['title'] as String? ?? '', 'curious');
    }
    sfx(Sfx.chat);
    // app in background → local alert (FCM covers the killed-app case)
    if (!LocalNotify.I.foreground) LocalNotify.I.showFromRow(n);
  }

  Future<void> markAll() async {
    unread = 0;
    for (var i = 0; i < recent.length; i++) {
      recent[i] = {...recent[i], 'read': true};
    }
    notifyListeners();
    await rpc('mark_notifications_read', {'p_ids': null}).catchError((_) => null);
  }

  Future<void> remove(JRow n) async {
    recent.removeWhere((x) => x['id'] == n['id']);
    notifyListeners();
    await supabase.from('notifications').delete().eq('id', n['id']).catchError((_) => <Map<String, dynamic>>[]);
  }
}

/// what tapping a notification does (shared with push / local notification taps)
Future<void> openNotification(Nav nav, Map data, String? kind, Toast toast) async {
  String? s(String k) => data[k] is String ? data[k] as String : null;
  switch (kind) {
    case 'dm':
      if (s('conversation') != null) return nav.openChat(s('conversation')!);
    case 'follow' || 'friend_request' || 'friend_accept':
      if (s('user') != null) return nav.openProfile(s('user')!);
    case 'club_invite' || 'club_request':
      if (s('club') != null) return nav.openClub(s('club')!);
    case 'room_invite':
      final rid = s('room');
      if (rid == null) return;
      try {
        final r = await rpc('join_room', {'p_room': rid, 'p_spectate': false});
        Matchmaker.I.pendingRoom = Map<String, dynamic>.from(r as Map);
        nav.openOnline(OnlineEntry.hub);
      } catch (e) {
        toast(errFa(e), 'err');
      }
      return;
    case 'match_found':
      return nav.openOnline(OnlineEntry.hub);
    default:
      if (s('tournament') != null) return nav.openOnline(OnlineEntry.tours);
  }
}

class NotificationsList extends StatefulWidget {
  final double bottom;
  final Toast toast;
  const NotificationsList({super.key, required this.bottom, required this.toast});
  @override
  State<NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<NotificationsList> {
  @override
  void initState() {
    super.initState();
    NotifFeed.I.refresh();
  }

  static (String?, Color) _look(String? k) => switch (k) {
        'dm' => (UI2['c_mega'], C.cyan),
        'follow' || 'friend_request' || 'friend_accept' => (UI2['x_player'], C.green),
        'club_invite' || 'club_request' => (UI2['x_shield'], C.gold),
        'room_invite' || 'match_found' => (UI2['x_ball'], C.red),
        'prize' => (UI2['x_trophy'], C.gold),
        _ => (UI2['c_bell'], C.violet),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: NotifFeed.I,
        builder: (context, _) {
          final f = NotifFeed.I, nav = NavScope.of(context);
          return RefreshIndicator(
            onRefresh: f.refresh,
            color: C.cyan,
            child: ListView(padding: EdgeInsets.fromLTRB(S.l, 0, S.l, widget.bottom + S.l), children: [
              if (f.unread > 0)
                Align(alignment: Alignment.centerLeft, child: Press(onPress: f.markAll, child: Padding(padding: const EdgeInsets.all(S.s), child: T('همه خوانده شد ✓', style: fs(F.bold, TS.small, color: C.cyan))))),
              if (f.recent.isEmpty)
                Empty(img: UI2['c_bell'], title: 'اعلانی نداری', sub: 'دعوت‌ها، پیام‌ها و درخواست‌های دوستی این‌جا نمایش داده می‌شوند')
              else
                for (final (i, n) in f.recent.indexed)
                  Dismissible(
                    key: ValueKey(n['id']),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => f.remove(n),
                    background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: S.l), child: T('حذف', style: fs(F.bold, 14, color: C.red))),
                    child: Enter(
                      i: i,
                      child: Press(
                        onPress: () {
                          if (n['read'] != true) rpc('mark_notifications_read', {'p_ids': [n['id']]}).catchError((_) => null);
                          openNotification(nav, (n['data'] as Map?) ?? const {}, n['kind'] as String?, widget.toast);
                        },
                        scaleTo: .98,
                        child: () {
                          final (img, c) = _look(n['kind'] as String?);
                          final unread = n['read'] != true;
                          return Container(
                            constraints: const BoxConstraints(minHeight: 64), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.all(S.s),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: unread ? c.withValues(alpha: .6) : C.line), color: unread ? c.withValues(alpha: .08) : rgba(10, 16, 44, .86)),
                            child: rrow([
                              Container(
                                width: 44, height: 44, alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: .15), border: Border.all(color: c.withValues(alpha: .5))),
                                child: Img(img, w: 28, h: 28),
                              ),
                              const SizedBox(width: S.s),
                              Expanded(
                                child: rcol([
                                  T(rs(n, 'title'), n: 2, style: fs(F.bold, TS.small)),
                                  if (n['body'] != null && '${n['body']}'.isNotEmpty) T('${n['body']}', n: 2, style: fs(F.body, TS.cap, color: C.dim)),
                                  T(timeAgo(n['created_at']), style: fs(F.body, TS.tiny, color: C.dim2)),
                                ]),
                              ),
                              if (unread) Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c)).animate(onPlay: (x) => x.repeat(reverse: true)).fade(begin: .4, duration: 800.ms),
                            ]),
                          );
                        }(),
                      ),
                    ),
                  ),
            ]),
          );
        },
      );
}
