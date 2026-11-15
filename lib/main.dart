// NEXORA (Flutter port) entry point: boot services, then the app shell (lib/app/shell.dart, port of App.tsx).
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/shell.dart';
import 'core/sound.dart';
import 'core/store.dart';
import 'net/auth.dart';
import 'net/discs.dart';
import 'net/supabase.dart';
import 'online/cup_alerts.dart';
import 'oracle/oracle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds swallow framework errors into a grey box; print them (logcat tag "flutter") so a device
  // log always says what broke.
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    debugPrint('NX_ERR ${d.exceptionAsString()}\n${d.stack}');
    prevOnError?.call(d);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('NX_ERR(async) $e\n$st');
    return true;
  };
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([Store.i.load(), initSupabase()]);
  Auth.i.init();
  Discs.i.init();
  Sound.init();
  Oracle.i.init();
  CupAlerts.i
    ..open = AppNav.openOnline
    ..init();
  runApp(const NexoraApp());
}
