// Crash / bug safety + network resilience.
//  * reportError: throttled, de-duplicated insert into public.client_errors (never throws)
//  * installErrorHandlers: FlutterError.onError, PlatformDispatcher.onError, ErrorWidget fallback
//  * NetWatch: connectivity + Supabase realtime health → reconnects the socket and refreshes auth/profile on recovery
import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthResponse;

import '../ui/theme.dart';
import 'auth.dart';
import 'supabase.dart';

String appVersion = '';
final Map<String, int> _seen = {};
int _sent = 0, _windowStart = 0;

Future<void> reportError(Object error, StackTrace? stack, {String kind = 'error', Map<String, dynamic>? context}) async {
  try {
    if (kDebugMode) debugPrint('[$kind] $error\n$stack');
    if (!ONLINE_CONFIGURED) return;
    final msg = error.toString();
    final key = '$kind:${msg.length > 160 ? msg.substring(0, 160) : msg}';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_seen[key] ?? 0) < 60000) return; // same error at most once a minute
    _seen[key] = now;
    if (now - _windowStart > 600000) {
      _windowStart = now;
      _sent = 0;
    }
    if (++_sent > 20) return; // at most 20 reports per 10 minutes
    final st = stack?.toString();
    await supabase.from('client_errors').insert({
      'user_id': Auth.I.uid,
      'kind': kind,
      'message': msg.length > 2000 ? msg.substring(0, 2000) : msg,
      'stack': st == null ? null : (st.length > 8000 ? st.substring(0, 8000) : st),
      'context': context ?? const {},
      'app_version': appVersion,
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
    });
  } catch (_) {}
}

void installErrorHandlers() {
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    // image decode / network image hiccups are noise, not crashes
    final lib = d.library ?? '';
    if (lib.contains('image resource service')) return;
    reportError(d.exception, d.stack, kind: 'flutter', context: {'library': lib, 'context': d.context?.toDescription() ?? ''});
  };
  PlatformDispatcher.instance.onError = (e, s) {
    reportError(e, s, kind: 'platform');
    return true; // handled → no crash
  };
  // a broken widget shows a calm placeholder instead of the red screen in release
  ErrorWidget.builder = (d) => kDebugMode
      ? ErrorWidget(d.exception)
      : Material(
          color: Colors.transparent,
          child: Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('…', style: TextStyle(color: C.dim)))),
        );
  PackageInfo.fromPlatform().then((p) => appVersion = '${p.version}+${p.buildNumber}', onError: (_) {});
}

/// connectivity watcher: exposes `online` and heals the realtime socket after a drop
class NetWatch extends ValueNotifier<bool> {
  NetWatch._() : super(true);
  static final NetWatch I = NetWatch._();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _beat;
  bool _wasOffline = false;

  void start() {
    if (kIsWeb) return;
    _sub = Connectivity().onConnectivityChanged.listen(_on, onError: (_) {});
    Connectivity().checkConnectivity().then(_on, onError: (_) {});
    // presence + socket health every 60 s while the app runs
    _beat = Timer.periodic(const Duration(seconds: 60), (_) => _heartbeat());
  }

  void _on(List<ConnectivityResult> r) {
    final on = r.any((x) => x != ConnectivityResult.none);
    if (on == value) return;
    value = on;
    if (!on) {
      _wasOffline = true;
    } else if (_wasOffline) {
      _wasOffline = false;
      _recover();
    }
  }

  Future<void> _recover() async {
    if (!ONLINE_CONFIGURED) return;
    try {
      // the realtime client reconnects by itself with backoff; refresh the session + profile so screens resync
      await supabase.auth.refreshSession().catchError((_) => AuthResponse());
      await Auth.I.refreshProfile();
    } catch (e, s) {
      reportError(e, s, kind: 'reconnect');
    }
  }

  Future<void> _heartbeat() async {
    if (!ONLINE_CONFIGURED || Auth.I.uid == null || !value) return;
    try {
      await supabase.rpc('touch_presence');
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _beat?.cancel();
    super.dispose();
  }
}

/// thin "offline" banner shown on top of everything while the network is down
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: NetWatch.I,
        builder: (_, on, _) => IgnorePointer(
          child: AnimatedSlide(
            offset: on ? const Offset(0, -1.2) : Offset.zero,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: rgba(90, 15, 36, .95), border: Border.all(color: C.red)),
                  child: Text('اتصال اینترنت برقرار نیست · تلاش دوباره…', textDirection: TextDirection.rtl, style: fs(F.fa, 12)),
                ),
              ),
            ),
          ),
        ),
      );
}
