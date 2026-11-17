import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// In-app updater for THIS app only (Flutter redesign line).
///
/// Reads releases of ashkanshams-dev/Nexora-Online and keeps only tags `redesign-<n>` (prerelease or full release)
/// whose notes carry `vc=<versionCode>`. The React Native app's "latest" release is never read.
/// The current versionCode is injected by CI (`--dart-define=APP_VC=<run number>`, same value as
/// `--build-number`).
class AppRelease {
  const AppRelease({required this.vc, required this.tag, required this.apkUrl, required this.notes, required this.size});
  final int vc;
  final String tag;
  final String apkUrl;
  final String notes;
  final int size;
}

class AppUpdater extends ChangeNotifier {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  static const int currentVc = int.fromEnvironment('APP_VC', defaultValue: 0);
  static const String repo = 'ashkanshams-dev/Nexora-Online';
  static const String tagPrefix = 'redesign-';
  static const String apkName = 'NEXORA-redesign-universal.apk';
  static const MethodChannel _ch = MethodChannel('nexora/updater');

  AppRelease? available;
  double? progress; // null = not downloading
  String? error;
  bool dismissed = false;
  Timer? _timer;
  AppLifecycleListener? _life;
  bool _checking = false;

  void start() {
    if (!Platform.isAndroid || currentVc <= 0) return;
    unawaited(check());
    _life ??= AppLifecycleListener(onResume: () => unawaited(check()));
    _timer ??= Timer.periodic(const Duration(minutes: 30), (_) => check());
  }

  static final RegExp _vcRe = RegExp(r'vc\s*=\s*(\d+)');

  /// Release body → plain notes for the update banner (no HTML, images or the vc= marker line).
  @visibleForTesting
  static String cleanNotes(String body) => body
      .split('\n')
      .where((String l) => !l.contains('vc='))
      .map((String l) => l.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '').trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  /// Picks the highest versionCode among this app's `redesign-*` releases (prerelease or full release; drafts skipped).
  @visibleForTesting
  static AppRelease? pickBest(List<dynamic> releases, int current) {
    AppRelease? best;
    for (final dynamic r in releases) {
      if (r is! Map) continue;
      final String tag = '${r['tag_name'] ?? ''}';
      if (!tag.startsWith(tagPrefix) || r['draft'] == true) continue;
      final String body = '${r['body'] ?? ''}';
      final Match? m = _vcRe.firstMatch(body);
      final int vc = m != null ? int.parse(m.group(1)!) : (int.tryParse(tag.substring(tagPrefix.length)) ?? 0);
      if (vc <= current) continue;
      final List<dynamic> assets = (r['assets'] as List<dynamic>?) ?? const <dynamic>[];
      Map<dynamic, dynamic>? apk;
      for (final dynamic a in assets) {
        if (a is Map && a['name'] == apkName) apk = a;
      }
      if (apk == null) continue;
      if (best == null || vc > best.vc) {
        best = AppRelease(
            vc: vc,
            tag: tag,
            apkUrl: '${apk['browser_download_url']}',
            notes: cleanNotes(body),
            size: (apk['size'] as num?)?.toInt() ?? 0);
      }
    }
    return best;
  }

  Future<void> check() async {
    if (_checking || progress != null) return;
    _checking = true;
    try {
      final HttpClient c = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final HttpClientRequest rq = await c.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=40'));
      rq.headers.set('Accept', 'application/vnd.github+json');
      rq.headers.set('User-Agent', 'nexora-app');
      final HttpClientResponse rs = await rq.close().timeout(const Duration(seconds: 20));
      if (rs.statusCode != 200) return;
      final String txt = await rs.transform(utf8.decoder).join();
      c.close();
      final AppRelease? r = pickBest(jsonDecode(txt) as List<dynamic>, currentVc);
      if (r != null && r.vc != available?.vc) {
        available = r;
        dismissed = false;
        notifyListeners();
      }
    } catch (_) {
      // offline / rate limited: try again on the next tick
    } finally {
      _checking = false;
    }
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    final AppRelease? r = available;
    if (r == null || progress != null) return;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final Directory dir = await getTemporaryDirectory();
      final Directory upd = Directory('${dir.path}/updates');
      if (upd.existsSync()) upd.deleteSync(recursive: true);
      upd.createSync(recursive: true);
      final File f = File('${upd.path}/nexora-${r.vc}.apk');
      final HttpClient c = HttpClient();
      final HttpClientRequest rq = await c.getUrl(Uri.parse(r.apkUrl));
      rq.headers.set('User-Agent', 'nexora-app');
      final HttpClientResponse rs = await rq.close();
      if (rs.statusCode != 200) throw Exception('HTTP ${rs.statusCode}');
      final int total = rs.contentLength > 0 ? rs.contentLength : r.size;
      final IOSink sink = f.openWrite();
      int got = 0;
      int lastPct = -1;
      await for (final List<int> chunk in rs) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final int pct = (got * 100 / total).floor();
          if (pct != lastPct) {
            lastPct = pct;
            progress = got / total;
            notifyListeners();
          }
        }
      }
      await sink.close();
      c.close();
      progress = 1;
      notifyListeners();
      final dynamic res = await _ch.invokeMethod<dynamic>('install', <String, String>{'path': f.path});
      if (res == 'needs_permission') {
        error = 'perm';
      }
    } catch (e) {
      error = '$e';
    } finally {
      progress = null;
      notifyListeners();
    }
  }
}
