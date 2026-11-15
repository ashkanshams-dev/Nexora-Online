import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/online/cloud_profile_sync.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(cloudSyncProvider).start();
    });
  }

  @override
  void dispose() {
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
