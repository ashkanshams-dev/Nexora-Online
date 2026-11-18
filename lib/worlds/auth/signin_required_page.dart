import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';

/// Shown to local guests who open an online-only screen (chat, social, tournaments, rankings, online lobbies).
/// Before, the router silently pushed a second home page instead, so these menus looked broken.
class SignInRequiredPage extends StatelessWidget {
  const SignInRequiredPage({super.key, required this.from});

  /// The path the guest tried to open (only used to pick the dock tab and the wording).
  final String from;

  Nx2Tab? get _tab {
    if (from == '/social' || from.startsWith('/world/orbit_network') || from.startsWith('/world/social_station') ||
        from.startsWith('/world/nova_gallery')) {
      return Nx2Tab.social;
    }
    if (from.startsWith('/tournaments') || from.startsWith('/t/')) return Nx2Tab.tournaments;
    return null;
  }

  bool get _isChat =>
      from == '/social' || from.startsWith('/world/orbit_network') || from.startsWith('/call/');

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return NxWorldScaffold(
      title: context.tx('ورود لازم است', 'SIGN IN REQUIRED'),
      palette: WorldPalette.social,
      showWallet: false,
      dock: _tab,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(_isChat ? Icons.forum_rounded : Icons.public_rounded, size: 72, color: Nx2.cyan),
                const SizedBox(height: 14),
                Text(
                  _isChat
                      ? context.tx('چت به حساب آنلاین نیاز دارد', 'Chat needs an online account')
                      : context.tx('این بخش به حساب آنلاین نیاز دارد', 'This section needs an online account'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: visual.text, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tx(
                      'الان در حالت مهمان (آفلاین) هستی. با ایمیل وارد شو تا چت، بازی آنلاین، تورنمنت و رتبه‌بندی باز شود. '
                          'بازی‌های آفلاین و با ربات بدون ورود هم در دسترس‌اند.',
                      'You are in guest (offline) mode. Sign in with your email to unlock chat, online games, '
                          'tournaments and rankings. Offline and vs-bot games keep working without an account.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: visual.muted, height: 1.5),
                ),
                const SizedBox(height: 22),
                Nx2Button(
                  label: context.tx('ورود با ایمیل', 'SIGN IN WITH EMAIL'),
                  icon: Icons.mark_email_read_rounded,
                  kind: Nx2ButtonKind.pink,
                  height: 56,
                  fontSize: 15,
                  onTap: () => context.go('/auth'),
                ),
                const SizedBox(height: 10),
                Nx2Button(
                  label: context.tx('بازی‌های آفلاین', 'OFFLINE GAMES'),
                  icon: Icons.sports_esports_rounded,
                  kind: Nx2ButtonKind.violet,
                  height: 48,
                  fontSize: 13,
                  onTap: () => context.pushReplacement('/world/nexora_arcade'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unknown route (bad deep link, stale notification). Before, the router showed a full home page here, which pushed
/// a duplicate hub onto the stack.
class RouteNotFoundPage extends StatelessWidget {
  const RouteNotFoundPage({super.key, required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return NxWorldScaffold(
      title: 'NEXORA',
      palette: WorldPalette.hub,
      showWallet: false,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(Icons.explore_off_rounded, size: 64, color: visual.muted),
            const SizedBox(height: 12),
            Text(context.tx('این صفحه پیدا نشد', 'This page was not found'),
                textAlign: TextAlign.center,
                style: TextStyle(color: visual.text, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.go('/hub'),
              icon: const Icon(Icons.home_rounded),
              label: Text(context.tx('خانه', 'Home')),
            ),
          ]),
        ),
      ),
    );
  }
}
