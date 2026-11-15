import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/online/call_watcher.dart';
import '../core/online/cloud_profile_sync.dart';
import '../core/online/invite_watcher.dart';
import '../core/online/online_service.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/nx_theme.dart';
import 'router.dart';

class NexoraApp extends ConsumerStatefulWidget {
  const NexoraApp({super.key});

  @override
  ConsumerState<NexoraApp> createState() => _NexoraAppState();
}

class _NexoraAppState extends ConsumerState<NexoraApp> {
  late final GoRouter _router = buildRouter(ref);
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey<ScaffoldMessengerState>();
  late final InviteWatcher _invites =
      InviteWatcher(ref, _messenger, (String game, String code) => _router.push('/online/$game?code=$code'));
  late final CallWatcher _calls = CallWatcher(ref, _messenger, (String chat, String call, bool video, String title) {
    _router.push(Uri(path: '/call/$chat', queryParameters: <String, String>{
      'call': call,
      'video': video ? '1' : '0',
      'title': title,
    }).toString());
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cloudSyncProvider).start();
      ref.read(onlineProvider).addListener(_invites.sync);
      _invites.sync();
      ref.read(onlineProvider).addListener(_calls.sync);
      _calls.sync();
    });
  }

  @override
  void dispose() {
    _invites.dispose();
    _calls.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'NEXORA',
      debugShowCheckedModeBanner: false,
      theme: buildNxTheme(),
      locale: settings.locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      scaffoldMessengerKey: _messenger,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: settings.reducedMotion || mq.disableAnimations,
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
