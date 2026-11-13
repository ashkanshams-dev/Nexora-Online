// NEXORA — Flutter entry point.
// Boot order: zone + error handlers → bindings → system UI → prefs (theme/lang) → i18n → store → sound → Supabase + auth
// → discs catalogue → local notifications → app. Network-dependent work never blocks the first frame.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'i18n/i18n.dart';
import 'net/auth.dart';
import 'net/discs.dart';
import 'net/guard.dart';
import 'net/notify.dart';
import 'net/supabase.dart';
import 'prefs.dart';
import 'sound.dart';
import 'store.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorHandlers();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ));

    Future<void> safe(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e, s) {
        reportError(e, s, kind: 'boot', context: {'step': what});
      }
    }

    await safe('prefs', loadPrefs);
    await safe('i18n', loadI18n);
    await safe('store', Store.I.load);
    await safe('sound', initSound);
    if (ONLINE_CONFIGURED) {
      await safe('supabase', initSupabase);
      await safe('auth', Auth.I.init);
      unawaited(safe('discs', Discs.I.init));
    }
    await safe('notify', LocalNotify.I.init);
    NetWatch.I.start();

    // e-mail links (nexora://auth#access_token=… / ?code=…)
    if (ONLINE_CONFIGURED) {
      try {
        final links = AppLinks();
        links.uriLinkStream.listen((u) {
          if (u.scheme == 'nexora' && u.host == 'auth') Auth.I.handleLink(u);
        }, onError: (_) {});
      } catch (_) {}
    }

    runApp(const NexoraApp());

    // push is optional and slow (Firebase); start it after the first frame
    if (ONLINE_CONFIGURED) {
      WidgetsBinding.instance.addPostFrameCallback((_) => LocalNotify.I.initPush());
      String? lastUid = Auth.I.uid;
      Auth.I.addListener(() {
        final u = Auth.I.uid;
        if (u != lastUid) {
          lastUid = u;
          if (u != null) LocalNotify.I.onSignedIn();
        }
      });
    }
  }, (e, s) => reportError(e, s, kind: 'zone'));
}
