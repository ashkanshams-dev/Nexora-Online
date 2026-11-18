import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/auth_link.dart';
import '../../core/online/cloud_profile_sync.dart';
import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

/// Lands here from the e-mail link `nexora://auth-callback?flow=...&code=...` (cold or warm start).
/// Exchanges the one-time PKCE code for a session and shows a clear Persian result.
class AuthCallbackPage extends ConsumerStatefulWidget {
  const AuthCallbackPage({super.key, required this.link});

  /// The callback location (`/auth/callback?...` or the raw deep link).
  final Uri link;

  @override
  ConsumerState<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends ConsumerState<AuthCallbackPage> {
  AuthLinkResult? _result;
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _pw2 = TextEditingController();
  bool _saving = false, _pwDone = false;
  String? _pwError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final OnlineService online = ref.read(onlineProvider);
    final AuthLinkResult r = await online.completeAuthLink(AuthCallback.fromUri(widget.link));
    if (!mounted) return;
    if (r.signedIn) {
      ref.read(settingsProvider).setAuthMode('email');
      ref.read(cloudSyncProvider).start();
    }
    setState(() => _result = r);
  }

  String get _next => ref.read(profileProvider).hasIdentity ? '/hub' : '/onboarding';

  Future<void> _savePassword() async {
    final String a = _pw.text, b = _pw2.text;
    if (a.length < 6) {
      setState(() => _pwError = context.tx('رمز عبور باید حداقل ۶ کاراکتر باشد.', 'Password must contain at least 6 characters.'));
      return;
    }
    if (a != b) {
      setState(() => _pwError = context.tx('دو رمز یکسان نیستند.', 'The passwords do not match.'));
      return;
    }
    setState(() {
      _saving = true;
      _pwError = null;
    });
    final OnlineService online = ref.read(onlineProvider);
    final bool ok = await online.changePassword(a);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _pwDone = ok;
      _pwError = ok ? null : context.tx('ذخیره‌ی رمز انجام نشد. دوباره تلاش کن.', 'Could not save the password. Try again.');
    });
  }

  ({IconData icon, Color color, String title, String body}) _copy(BuildContext context, AuthLinkResult r) {
    switch (r.outcome) {
      case AuthLinkOutcome.signedIn:
        final bool change = r.flow == AuthLinkFlow.emailChange;
        final bool magic = r.flow == AuthLinkFlow.magicLink;
        return (
          icon: Icons.verified_rounded,
          color: NxColors.success,
          title: change
              ? context.tx('ایمیل جدید تأیید شد', 'New email confirmed')
              : magic
                  ? context.tx('وارد شدی', 'You are signed in')
                  : context.tx('حسابت تأیید شد', 'Your account is verified'),
          body: context.tx('خوش آمدی! با همین حساب وارد NEXORA شدی و پیشرفتت ذخیره می‌شود.',
              'Welcome! You are signed in to NEXORA and your progress is saved.'),
        );
      case AuthLinkOutcome.recovery:
        return (
          icon: Icons.lock_reset_rounded,
          color: NxColors.success,
          title: _pwDone ? context.tx('رمز جدید ذخیره شد', 'New password saved') : context.tx('رمز جدید انتخاب کن', 'Choose a new password'),
          body: _pwDone
              ? context.tx('از این به بعد با رمز جدید وارد شو.', 'Use the new password from now on.')
              : context.tx('لینک بازیابی تأیید شد. رمز تازه‌ات را وارد کن.', 'The reset link is verified. Enter your new password.'),
        );
      case AuthLinkOutcome.confirmedSignInNeeded:
        return (
          icon: Icons.mark_email_read_rounded,
          color: NxColors.success,
          title: context.tx('ایمیلت تأیید شد', 'Your email is confirmed'),
          body: context.tx(
              'این لینک روی گوشی‌ای باز شد که ثبت‌نام از آن انجام نشده بود (یا قبلاً استفاده شده). حالا با ایمیل و رمز عبورت وارد شو.',
              'This link was opened on a different phone (or was already used). Sign in with your email and password now.'),
        );
      case AuthLinkOutcome.expired:
        return (
          icon: Icons.timer_off_rounded,
          color: NxColors.danger,
          title: context.tx('لینک منقضی شده', 'The link has expired'),
          body: context.tx('این لینک دیگر معتبر نیست یا قبلاً استفاده شده. از صفحه‌ی ورود یک لینک یا کد تازه بگیر.',
              'This link is no longer valid or was already used. Request a new link or code from the sign-in screen.'),
        );
      case AuthLinkOutcome.invalid:
        return (
          icon: Icons.link_off_rounded,
          color: NxColors.danger,
          title: context.tx('لینک نامعتبر', 'Invalid link'),
          body: context.tx('این لینک اطلاعات ورود ندارد. لینک داخل ایمیل را دوباره باز کن.',
              'This link has no sign-in data. Open the link in the email again.'),
        );
      case AuthLinkOutcome.notConfigured:
      case AuthLinkOutcome.failed:
        return (
          icon: Icons.error_outline_rounded,
          color: NxColors.danger,
          title: context.tx('تأیید انجام نشد', 'Verification failed'),
          body: context.tx('ورود از طریق لینک کامل نشد. اتصال اینترنت را بررسی کن و دوباره لینک را باز کن.',
                  'The link sign-in did not finish. Check your connection and open the link again.') +
              (r.detail == null ? '' : '\n(${r.detail})'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final AuthLinkResult? r = _result;
    final List<Widget> children = <Widget>[];
    if (r == null) {
      children.addAll(<Widget>[
        const OracleAvatar(pose: 'hero_wave', size: 112),
        const SizedBox(height: 18),
        Text(context.tx('در حال تأیید لینک…', 'Verifying the link…'),
            textAlign: TextAlign.center, style: TextStyle(color: visual.text, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
      ]);
    } else {
      final c = _copy(context, r);
      children.addAll(<Widget>[
        Icon(c.icon, size: 84, color: c.color),
        const SizedBox(height: 14),
        Text(c.title, textAlign: TextAlign.center, style: TextStyle(color: visual.text, fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(c.body, textAlign: TextAlign.center, style: TextStyle(color: visual.muted, height: 1.5)),
        const SizedBox(height: 24),
      ]);
      if (r.outcome == AuthLinkOutcome.recovery && !_pwDone) {
        children.addAll(<Widget>[
          TextField(
              controller: _pw,
              enabled: !_saving,
              obscureText: true,
              decoration: InputDecoration(labelText: context.tx('رمز جدید', 'New password'), prefixIcon: const Icon(Icons.lock_outline_rounded))),
          const SizedBox(height: 10),
          TextField(
              controller: _pw2,
              enabled: !_saving,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: context.tx('تکرار رمز جدید', 'Repeat new password'), prefixIcon: const Icon(Icons.lock_outline_rounded))),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _saving ? null : _savePassword,
              icon: const Icon(Icons.save_rounded),
              label: Text(context.tx('ذخیره‌ی رمز', 'Save password'))),
          if (_saving) ...<Widget>[const SizedBox(height: 10), const LinearProgressIndicator()],
          if (_pwError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_pwError!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 8),
          TextButton(onPressed: _saving ? null : () => context.go(_next), child: Text(context.tx('بعداً', 'Later'))),
        ]);
      } else if (r.signedIn) {
        children.add(FilledButton.icon(
            onPressed: () => context.go(_next),
            icon: const Icon(Icons.rocket_launch_rounded),
            label: Text(context.tx('ورود به NEXORA', 'Enter NEXORA'))));
      } else {
        children.add(FilledButton.icon(
            onPressed: () => context.go('/auth'),
            icon: const Icon(Icons.login_rounded),
            label: Text(context.tx('رفتن به صفحه‌ی ورود', 'Go to sign in'))));
      }
    }
    return Scaffold(
      backgroundColor: visual.background,
      body: NxBrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
