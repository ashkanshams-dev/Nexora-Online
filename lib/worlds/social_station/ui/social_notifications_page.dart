import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/online/online_service.dart';
import '../data/social_profile_repository.dart';

class SocialNotificationsPage extends ConsumerStatefulWidget {
  const SocialNotificationsPage({super.key});
  @override
  ConsumerState<SocialNotificationsPage> createState() => _SocialNotificationsPageState();
}

class _SocialNotificationsPageState extends ConsumerState<SocialNotificationsPage> {
  Future<List<SocialNotification>>? _future;
  SocialProfileRepository? _repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final online = ref.read(onlineProvider);
    if (online.client != null && online.user != null) {
      _repo = SocialProfileRepository(online.client!);
      _future = _repo!.notifications();
    }
  }

  String _title(SocialNotification n) {
    switch (n.kind) {
      case 'follow': return 'یک نفر شما را دنبال کرد';
      case 'follow_request': return 'درخواست دنبال‌کردن جدید';
      case 'follow_accepted': return 'درخواست دنبال‌کردن پذیرفته شد';
      case 'message': return 'پیام جدید';
      default: return 'اعلان جدید';
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    final future = _future;
    if (future != null) await future;
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: future == null
          ? const Center(child: Text('ورود لازم است'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<SocialNotification>>(
                future: future,
                builder: (BuildContext context, AsyncSnapshot<List<SocialNotification>> snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final list = snapshot.data!;
                  if (list.isEmpty) return const Center(child: Text('اعلانی وجود ندارد'));
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int index) {
                      final notification = list[index];
                      return ListTile(
                        tileColor: notification.read ? null : Theme.of(context).colorScheme.primary.withValues(alpha: .08),
                        leading: Icon(notification.kind == 'message' ? Icons.chat_bubble_outline : Icons.notifications_none),
                        title: Text(_title(notification)),
                        subtitle: Text(notification.createdAt.toLocal().toString()),
                        onTap: () async {
                          if (notification.read || _repo == null) return;
                          await _repo!.markNotificationRead(notification.id);
                          if (mounted) setState(_load);
                        },
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
