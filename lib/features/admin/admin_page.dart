import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/online_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import 'admin_access.dart';

/// Admin panel. Tabs appear only for the permissions the signed-in admin holds; the server checks every call again
/// (auth project: users/bans, grants, admins, announcements, moderation, ORACLE · games project: rooms, tournaments)
/// and writes an audit entry.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _Tab {
  const _Tab(this.id, this.fa, this.en, this.icon);
  final String id, fa, en;
  final IconData icon;
}

class _AdminPageState extends ConsumerState<AdminPage> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(adminAccessProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    final List<_Tab> tabs = <_Tab>[
      const _Tab('home', 'خلاصه', 'Overview', Icons.dashboard_rounded),
      if (a.can(AdminPerm.users) || a.can(AdminPerm.currency))
        const _Tab('users', 'کاربران', 'Users', Icons.people_alt_rounded),
      if (a.can(AdminPerm.admins)) const _Tab('admins', 'ادمین‌ها', 'Admins', Icons.admin_panel_settings_rounded),
      if (a.can(AdminPerm.tournaments)) const _Tab('tournaments', 'تورنمنت', 'Tournaments', Icons.emoji_events_rounded),
      if (a.can(AdminPerm.moderation)) const _Tab('moderation', 'نظارت', 'Moderation', Icons.shield_rounded),
      if (a.can(AdminPerm.rooms)) const _Tab('rooms', 'اتاق‌ها', 'Rooms', Icons.meeting_room_rounded),
      if (a.can(AdminPerm.announcements)) const _Tab('announcements', 'اطلاعیه', 'Announcements', Icons.campaign_rounded),
      if (a.can(AdminPerm.oracle)) const _Tab('oracle', 'اوراکل', 'ORACLE', Icons.psychology_alt_rounded),
      if (a.can(AdminPerm.admins)) const _Tab('audit', 'گزارش', 'Audit log', Icons.receipt_long_rounded),
    ];
    if (!a.loaded) {
      return const Scaffold(backgroundColor: NxColors.navyDeep, body: Center(child: CircularProgressIndicator()));
    }
    if (!a.isAdmin) {
      return Scaffold(
        backgroundColor: NxColors.navyDeep,
        appBar: AppBar(title: Text(context.tx('پنل مدیریت', 'Admin panel'))),
        body: Center(child: Text(context.tx('این بخش فقط برای ادمین‌هاست.', 'Admins only.'))),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: NxColors.navyDeep,
        appBar: AppBar(
          backgroundColor: NxColors.navy,
          title: Text(a.owner ? context.tx('پنل مدیر اصلی', 'Main admin panel') : context.tx('پنل مدیریت', 'Admin panel')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: NxColors.gold,
            tabs: <Widget>[
              for (final _Tab t in tabs) Tab(icon: Icon(t.icon, size: 20), text: context.tx(t.fa, t.en)),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[
          for (final _Tab t in tabs)
            switch (t.id) {
              'home' => const _Overview(),
              'users' => const _UsersTab(),
              'admins' => const _AdminsTab(),
              'tournaments' => const _TournamentsTab(),
              'moderation' => const _ModerationTab(),
              'rooms' => const _RoomsTab(),
              'announcements' => const _AnnouncementsTab(),
              'oracle' => const _OracleTab(),
              _ => const _AuditTab(),
            },
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers
AdminApi _api(WidgetRef ref) => AdminApi(ref.read(onlineProvider));

Future<void> _toast(BuildContext context, Map<String, dynamic> r, {String? okFa, String? okEn}) async {
  if (!context.mounted) return;
  final bool fa = context.isFa;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(r['ok'] == true ? (fa ? (okFa ?? 'انجام شد ✓') : (okEn ?? 'Done ✓')) : adminErrorText(r['error'] as String?, fa)),
  ));
}

Future<String?> _ask(BuildContext context, String title, {String hint = '', String initial = ''}) async {
  final TextEditingController c = TextEditingController(text: initial);
  final String? r = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tx('انصراف', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tx('تأیید', 'OK'))),
      ],
    ),
  );
  c.dispose();
  return r;
}

Widget _card({required Widget child}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NxColors.glassBorder),
      ),
      child: child,
    );

String _shortTime(Object? iso) {
  final DateTime? t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Loads a JSON result once and shows a list; pull to refresh.
class _Loader extends StatefulWidget {
  const _Loader({required this.load, required this.build});
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, VoidCallback reload) build;

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    widget.load().then((Map<String, dynamic> d) {
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    if (d['ok'] != true) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(adminErrorText(d['error'] as String?, context.isFa)),
        TextButton(onPressed: _reload, child: Text(context.tx('دوباره', 'Retry'))),
      ]));
    }
    return RefreshIndicator(onRefresh: () async => _reload(), child: widget.build(context, d, _reload));
  }
}

// ------------------------------------------------------------------ overview
class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    return _Loader(
      load: () => _api(ref).stats(),
      build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
        Widget stat(String fa, String en, Object? v, IconData icon) => _card(
                child: Row(children: <Widget>[
              Icon(icon, color: NxColors.gold),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tx(fa, en))),
              Text('${v ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ]));
        return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(a.owner ? context.tx('تو مدیر اصلی هستی — همه‌ی دسترسی‌ها', 'You are the main admin — every permission') : context.tx('دسترسی‌های تو', 'Your permissions'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final String p in AdminPerm.all)
                if (a.can(p)) Chip(label: Text(AdminPerm.label(p, context.isFa)), visualDensity: VisualDensity.compact),
            ]),
          ])),
          stat('کاربران', 'Users', d['users'], Icons.people_rounded),
          stat('مهمان‌ها', 'Guests', d['guests'], Icons.person_outline_rounded),
          stat('مسدود', 'Banned', d['banned'], Icons.block_rounded),
          stat('مدیران تورنمنت', 'Tournament managers', d['organizers'], Icons.emoji_events_rounded),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ users
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final TextEditingController _q = TextEditingController();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final Map<String, dynamic> r = await _api(ref).users(_q.text.trim());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _err = r['ok'] == true ? null : adminErrorText(r['error'] as String?, context.isFa);
      _rows = ((r['users'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  Future<void> _grant(Map<String, dynamic> u) async {
    final TextEditingController coins = TextEditingController(text: '0');
    final TextEditingController gems = TextEditingController(text: '0');
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('اهدا به ${u['username'] ?? ''}', 'Grant to ${u['username'] ?? ''}')),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(controller: coins, keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: ctx.tx('سکه (منفی = کسر)', 'Coins (negative = take)'))),
          TextField(controller: gems, keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: ctx.tx('جم (منفی = کسر)', 'Gems (negative = take)'))),
          TextField(controller: reason, decoration: InputDecoration(labelText: ctx.tx('دلیل', 'Reason'))),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ثبت', 'Grant'))),
        ],
      ),
    );
    if (ok == true) {
      final Map<String, dynamic> r = await _api(ref).grant(
          '${u['id']}', int.tryParse(coins.text.trim()) ?? 0, int.tryParse(gems.text.trim()) ?? 0, reason.text.trim());
      if (mounted) await _toast(context, r);
      unawaited(_search());
    }
    coins.dispose();
    gems.dispose();
    reason.dispose();
  }

  Future<void> _ban(Map<String, dynamic> u) async {
    final bool banned = u['banned'] == true;
    String? reason;
    if (!banned) {
      reason = await _ask(context, context.tx('دلیل مسدودسازی', 'Ban reason'));
      if (reason == null) return;
    }
    final Map<String, dynamic> r = await _api(ref).ban('${u['id']}', !banned, reason);
    if (mounted) await _toast(context, r);
    unawaited(_search());
  }

  @override
  Widget build(BuildContext context) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: context.tx('نام کاربری، ایمیل یا شناسه', 'Username, email or id'),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!)),
      Expanded(
        child: ListView.builder(
          itemCount: _rows.length,
          itemBuilder: (BuildContext context, int i) {
            final Map<String, dynamic> u = _rows[i];
            final bool banned = u['banned'] == true;
            return _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Icon(banned ? Icons.block_rounded : Icons.person_rounded, color: banned ? NxColors.danger : NxColors.turquoise),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${u['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900))),
                Text('${u['role']}', style: const TextStyle(color: NxColors.gold, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${u['guest'] == true ? context.tx('مهمان', 'guest') : (u['email'] ?? '')} · Lv ${u['level']} · '
                  '🪙 ${u['coins']} · 💎 ${u['gems']}',
                  style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
              if (banned && (u['ban_reason'] ?? '').toString().isNotEmpty)
                Text('⛔ ${u['ban_reason']}', style: const TextStyle(color: NxColors.danger, fontSize: 12)),
              Wrap(spacing: 6, children: <Widget>[
                if (a.can(AdminPerm.currency))
                  TextButton.icon(
                      onPressed: () => _grant(u),
                      icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                      label: Text(context.tx('اهدا', 'Grant'))),
                if (a.can(AdminPerm.users) && u['role'] != 'owner')
                  TextButton.icon(
                      onPressed: () => _ban(u),
                      icon: Icon(banned ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
                      label: Text(banned ? context.tx('رفع مسدودی', 'Unban') : context.tx('مسدود', 'Ban'))),
                if (a.can(AdminPerm.admins) && u['role'] != 'owner' && u['guest'] != true)
                  TextButton.icon(
                      onPressed: () => showAdminEditor(context, ref, u),
                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                      label: Text(context.tx('دسترسی', 'Access'))),
              ]),
            ]));
          },
        ),
      ),
    ]);
  }
}

/// Edit one admin's permissions (+ tournament manager gem options).
Future<void> showAdminEditor(BuildContext context, WidgetRef ref, Map<String, dynamic> u, {VoidCallback? done}) async {
  final AdminAccess me = ref.read(adminAccessProvider);
  final Set<String> perms = ((u['perms'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();
  bool unlimited = u['unlimited_gems'] == true || u['unlimited'] == true;
  final TextEditingController budget = TextEditingController(text: '${u['gem_budget'] ?? 0}');
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => AlertDialog(
        title: Text(ctx.tx('دسترسی ${u['username'] ?? ''}', 'Access · ${u['username'] ?? ''}')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (final String p in AdminPerm.all)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: perms.contains(p),
                title: Text(AdminPerm.label(p, ctx.isFa)),
                onChanged: (p == AdminPerm.admins && !me.owner)
                    ? null
                    : (bool? v) => set(() => v == true ? perms.add(p) : perms.remove(p)),
              ),
            const Divider(),
            Text(ctx.tx('جایزه‌ی جم در تورنمنت‌هایش', 'Gem prizes in their tournaments'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: unlimited,
              title: Text(ctx.tx('نامحدود (فقط مدیر اصلی)', 'Unlimited (main admin only)')),
              onChanged: me.owner ? (bool v) => set(() => unlimited = v) : null,
            ),
            if (!unlimited)
              TextField(
                controller: budget,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ctx.tx('سقف جم', 'Gem budget')),
              ),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('ذخیره', 'Save'))),
        ],
      ),
    ),
  );
  if (ok == true) {
    final int b = int.tryParse(budget.text.trim()) ?? 0;
    final Map<String, dynamic> r = await _api(ref).setPerms('${u['id']}', perms.toList(),
        unlimitedGems: unlimited, gemBudget: unlimited ? null : b);
    if (r['ok'] == true && perms.contains(AdminPerm.tournaments) == false && (b > 0 || unlimited)) {
      // a manager without the tournaments permission: organizer role with the gem option
      await _api(ref).setManager('${u['id']}', true, unlimited: unlimited, gemBudget: b);
    }
    if (context.mounted) await _toast(context, r);
    done?.call();
  }
  budget.dispose();
}

// ------------------------------------------------------------------ admins
class _AdminsTab extends ConsumerWidget {
  const _AdminsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).admins(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['admins'] as List<dynamic>?) ?? const <dynamic>[];
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Text(
                    context.tx('برای افزودن ادمین، کاربر را در زبانه‌ی «کاربران» پیدا کن و «دسترسی» را بزن.',
                        'To add an admin, find the user in Users and tap Access.'),
                    style: const TextStyle(color: NxColors.textDim))),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> u = Map<String, dynamic>.from(e as Map);
                final List<dynamic> p = (u['perms'] as List<dynamic>?) ?? const <dynamic>[];
                return _card(
                    child: Row(children: <Widget>[
                  Icon(u['owner'] == true ? Icons.workspace_premium_rounded : Icons.shield_rounded,
                      color: u['owner'] == true ? NxColors.gold : NxColors.turquoise),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${u['username'] ?? 'Pilot'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                        u['owner'] == true
                            ? context.tx('مدیر اصلی — همه‌ی دسترسی‌ها', 'Main admin — everything')
                            : <String>[
                                for (final dynamic x in p) AdminPerm.label('$x', context.isFa),
                                if (u['staff_role'] == 'organizer') context.tx('مدیر تورنمنت', 'tournament manager'),
                                if (u['unlimited_gems'] == true) context.tx('جم نامحدود', 'unlimited gems')
                                else if (u['gem_budget'] != null) context.tx('سقف جم ${u['gem_budget']}', 'gem budget ${u['gem_budget']}'),
                              ].join(' · '),
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  ])),
                  if (u['owner'] != true)
                    IconButton(
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => showAdminEditor(context, ref, u, done: reload)),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ tournaments
class _TournamentsTab extends ConsumerWidget {
  const _TournamentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).tournaments(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['tournaments'] as List<dynamic>?) ?? const <dynamic>[];
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Row(children: <Widget>[
              Expanded(child: Text(context.tx('ساخت تورنمنت جدید', 'Create a tournament'))),
              FilledButton.icon(
                  onPressed: () => context.push('/tournaments/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tx('جدید', 'New'))),
            ])),
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> t = Map<String, dynamic>.from(e as Map);
                return _card(
                    child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      '${t['game']} · ${t['status']} · ${t['players']}/${t['capacity']} · ${t['creator'] ?? ''}'
                      '${(t['disputes'] ?? 0) > 0 ? ' · ⚠ ${t['disputes']}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/tournaments/${t['id']}/manage'),
                ));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ moderation
class _ModerationTab extends ConsumerWidget {
  const _ModerationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).recentContent(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          Future<void> remove(String kind, String id) async {
            final String? reason = await _ask(context, context.tx('دلیل حذف', 'Reason for removal'));
            if (reason == null) return;
            final Map<String, dynamic> r = await _api(ref).remove(kind, id, reason);
            if (context.mounted) await _toast(context, r);
            reload();
          }

          Widget item(String kind, Map<String, dynamic> m) => _card(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Icon(kind == 'post' ? Icons.photo_rounded : Icons.chat_bubble_rounded, color: NxColors.turquoise),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${m['username'] ?? 'Pilot'} · ${_shortTime(m['created_at'])}',
                      style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  Text('${m['text'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
                ])),
                IconButton(
                    icon: const Icon(Icons.delete_forever_rounded, color: NxColors.danger),
                    onPressed: () => remove(kind, '${m['id']}')),
              ]));
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(context.tx('پست‌ها و استوری‌های اخیر', 'Recent posts & stories'),
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            for (final dynamic e in (d['posts'] as List<dynamic>?) ?? const <dynamic>[])
              item('post', Map<String, dynamic>.from(e as Map)),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(context.tx('نظرهای اخیر', 'Recent comments'), style: const TextStyle(fontWeight: FontWeight.w900))),
            for (final dynamic e in (d['comments'] as List<dynamic>?) ?? const <dynamic>[])
              item('comment', Map<String, dynamic>.from(e as Map)),
          ]);
        },
      );
}

// ------------------------------------------------------------------ rooms
class _RoomsTab extends ConsumerWidget {
  const _RoomsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).rooms(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          final List<dynamic> rows = (d['rooms'] as List<dynamic>?) ?? const <dynamic>[];
          if (rows.isEmpty) {
            return ListView(children: <Widget>[
              const SizedBox(height: 80),
              Center(child: Text(context.tx('اتاق فعالی نیست', 'No active rooms'))),
            ]);
          }
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            for (final dynamic e in rows)
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> r = Map<String, dynamic>.from(e as Map);
                final Map<String, dynamic> st = Map<String, dynamic>.from((r['settings'] as Map?) ?? const <String, dynamic>{});
                return _card(
                    child: Row(children: <Widget>[
                  Icon(r['status'] == 'playing' ? Icons.sports_esports_rounded : Icons.meeting_room_rounded,
                      color: NxColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${r['game']} · ${r['code']}${st['tmatch'] != null ? ' · 🏆' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                        '${r['status']} · ${r['players']}/${r['seats']} · ${r['is_private'] == true ? context.tx('خصوصی', 'private') : context.tx('عمومی', 'public')}'
                        '${st['category'] != null ? ' · ${st['category']}' : ''} · ${r['host_name'] ?? ''}',
                        style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                  ])),
                  IconButton(
                    tooltip: context.tx('بستن اتاق', 'Close room'),
                    icon: const Icon(Icons.cancel_rounded, color: NxColors.danger),
                    onPressed: () async {
                      final String? reason = await _ask(context, context.tx('دلیل بستن اتاق', 'Reason'));
                      if (reason == null) return;
                      final Map<String, dynamic> x = await _api(ref).closeRoom('${r['id']}', reason);
                      if (context.mounted) await _toast(context, x);
                      reload();
                    },
                  ),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ announcements
class _AnnouncementsTab extends ConsumerWidget {
  const _AnnouncementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).announcements(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) {
          Future<void> create() async {
            final TextEditingController title = TextEditingController();
            final TextEditingController body = TextEditingController();
            int hours = 72;
            final bool? ok = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => StatefulBuilder(
                builder: (BuildContext ctx, StateSetter set) => AlertDialog(
                  title: Text(ctx.tx('اطلاعیه‌ی جدید', 'New announcement')),
                  content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    TextField(controller: title, decoration: InputDecoration(labelText: ctx.tx('عنوان', 'Title'))),
                    TextField(
                        controller: body,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(labelText: ctx.tx('متن', 'Text'))),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: hours,
                      isExpanded: true,
                      items: <DropdownMenuItem<int>>[
                        for (final int h in const <int>[6, 24, 72, 168, 0])
                          DropdownMenuItem<int>(
                              value: h,
                              child: Text(h == 0 ? ctx.tx('بدون انقضا', 'No expiry') : ctx.tx('$h ساعت', '$h hours'))),
                      ],
                      onChanged: (int? v) => set(() => hours = v ?? 72),
                    ),
                  ]),
                  actions: <Widget>[
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('انتشار', 'Publish'))),
                  ],
                ),
              ),
            );
            if (ok == true) {
              final Map<String, dynamic> r = await _api(ref).announce(title.text.trim(), body.text.trim(), hours);
              if (context.mounted) await _toast(context, r, okFa: 'برای همه منتشر شد', okEn: 'Published to everyone');
              reload();
            }
            title.dispose();
            body.dispose();
          }

          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
            _card(
                child: Row(children: <Widget>[
              Expanded(child: Text(context.tx('اطلاعیه برای همه‌ی بازیکن‌ها', 'Announcement to every player'))),
              FilledButton.icon(onPressed: create, icon: const Icon(Icons.campaign_rounded), label: Text(context.tx('جدید', 'New'))),
            ])),
            for (final dynamic e in (d['items'] as List<dynamic>?) ?? const <dynamic>[])
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> a = Map<String, dynamic>.from(e as Map);
                final bool live = a['active'] == true;
                return _card(
                    child: Row(children: <Widget>[
                  Icon(Icons.campaign_rounded, color: live ? NxColors.gold : NxColors.textDim),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${a['body']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    Text(_shortTime(a['created_at']), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                  ])),
                  if (live)
                    TextButton(
                        onPressed: () async {
                          final Map<String, dynamic> r = await _api(ref).endAnnouncement((a['id'] as num).toInt());
                          if (context.mounted) await _toast(context, r);
                          reload();
                        },
                        child: Text(context.tx('پایان', 'End'))),
                ]));
              }),
          ]);
        },
      );
}

// ------------------------------------------------------------------ ORACLE
class _OracleTab extends StatelessWidget {
  const _OracleTab();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: <Widget>[
        _card(
            child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_alt_rounded, color: NxColors.gold),
          title: Text(context.tx('ویرایش شخصیت اوراکل', 'Edit ORACLE personality')),
          subtitle: Text(context.tx('بازیکن‌ها، جمله‌ها، خوشامدها، آموزش‌ها، تور و تنظیمات — با فرم',
              'Players, lines, greetings, tutorials, tour and settings — as a form')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/admin/oracle'),
        )),
      ]);
}

// ------------------------------------------------------------------ audit
class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Loader(
        load: () => _api(ref).audit(),
        build: (BuildContext context, Map<String, dynamic> d, VoidCallback reload) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: <Widget>[
            for (final dynamic e in (d['entries'] as List<dynamic>?) ?? const <dynamic>[])
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic> x = Map<String, dynamic>.from(e as Map);
                return _card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${x['action']} · ${x['actor_name'] ?? ''}${x['target_name'] != null ? ' → ${x['target_name']}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(_shortTime(x['created_at']), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                  if (x['data'] != null)
                    Text('${x['data']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ]));
              }),
          ],
        ),
      );
}
