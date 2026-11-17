import 'package:flutter/material.dart';

import 'app_updater.dart';

/// Floating "new version" card shown over the whole app (top of the stack).
class UpdateOverlay extends StatelessWidget {
  const UpdateOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppUpdater u = AppUpdater.instance;
    return Stack(children: <Widget>[
      child,
      ListenableBuilder(
        listenable: u,
        builder: (BuildContext context, _) {
          final AppRelease? r = u.available;
          if (r == null || (u.dismissed && u.progress == null)) return const SizedBox.shrink();
          final bool fa = Localizations.maybeLocaleOf(context)?.languageCode == 'fa';
          final double? p = u.progress;
          return Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 92,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: <Color>[Color(0xF0121A3F), Color(0xF0241046)]),
                  border: Border.all(color: const Color(0xFF39E6FF), width: 1.2),
                  boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x6639E6FF), blurRadius: 22)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Row(children: <Widget>[
                    const Icon(Icons.system_update_rounded, color: Color(0xFF39E6FF)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fa ? 'نسخه جدید NEXORA آماده است (${r.vc})' : 'New NEXORA update available (${r.vc})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (p == null)
                      TextButton(
                        onPressed: u.dismiss,
                        child: Text(fa ? 'بعداً' : 'Later', style: const TextStyle(color: Colors.white70)),
                      ),
                    if (p == null)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF39E6FF), foregroundColor: Colors.black),
                        onPressed: u.downloadAndInstall,
                        child: Text(fa ? 'به‌روزرسانی' : 'Update'),
                      ),
                  ]),
                  if (p != null) ...<Widget>[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: p, minHeight: 8, backgroundColor: Colors.white12, color: const Color(0xFF39E6FF)),
                    ),
                    const SizedBox(height: 6),
                    Text('${(p * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                  if (u.error != null && p == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        u.error == 'perm'
                            ? (fa ? 'اجازه نصب از این برنامه را بدهید و دوباره بزنید.' : 'Allow installs from NEXORA, then tap Update again.')
                            : (fa ? 'دانلود ناموفق بود؛ دوباره تلاش کنید.' : 'Download failed, tap Update to retry.'),
                        style: const TextStyle(color: Color(0xFFFFB86B), fontSize: 12),
                      ),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
