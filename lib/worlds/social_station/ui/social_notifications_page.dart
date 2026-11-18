import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/online/online_service.dart';
import '../data/social_profile_repository.dart';

class SocialNotificationsPage extends ConsumerStatefulWidget {
  const SocialNotificationsPage({super.key});
  @override ConsumerState<SocialNotificationsPage> createState() => _SocialNotificationsPageState();
}

class _SocialNotificationsPageState extends ConsumerState<SocialNotificationsPage> {
  Future<List<SocialNotification>>? _future;
  SocialProfileRepository? _repo;
  @override void initState() { super.initState(); _load(); }
  void _load() {
    final online = ref.read(onlineProvider);
    if (online.client != null && online.user != null) { _repo = SocialProfileRepository(online.client!); _future = _repo!.notifications(); }
  }
  String _title(SocialNotification n) => switch (n.kind) { 'follow' => 'یک نفر شما را دنبال کرد', 'follow_request' => 'درخواست دنبال‌کردن جدید', 'follow_accepted' => 'درخواست دنبال‌کردن پذیرفته شد', 'message' => 'پیام جدید', _ => 'اعلان جدید' };
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Notifications')), body: RefreshIndicator(onRefresh: () async { setState(_load); final f = _future; if (f != null) await f; }, child: _future == null ? const Center(child: Text('ورود لازم است')) : FutureBuilder<List<SocialNotification>>(future: _future, builder: (_, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); final list = snapshot.data!; if (list.isEmpty) return const Center(child: Text('اعلانی وجود ندارد')); return ListView.builder(itemCount: list.length, itemBuilder: (_, i) { final n = list[i]; return ListTile(tileColor: n.read ? null : Theme.of(context).colorScheme.primary.withValues(alpha: .08), leading: Icon(n.kind == 'message' ? Icons.chat_bubble_outline : Icons.notifications_none), title: Text(_title(n)), subtitle: Text(n.createdAt.toLocal().toString()), onTap: () async { if (!n.read) { await _repo!.markNotificationRead(n.id); if (mounted) setState(_load); } }); }); }))));
}
