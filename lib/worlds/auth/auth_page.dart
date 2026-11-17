import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final String email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = context.tx('ایمیل معتبر وارد کن.', 'Enter a valid email address.'));
      return;
    }
    final OnlineService online = ref.read(onlineProvider);
    if (!online.configured) {
      setState(() => _error = context.tx('اتصال آنلاین تنظیم نشده است.', 'Online authentication is not configured.'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.sendEmailOtp(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
      _error = ok ? null : _friendly(online.lastError);
    });
  }

  Future<void> _verifyCode() async {
    final String code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = context.tx('کد باید ۶ رقم باشد.', 'The code must be 6 digits.'));
      return;
    }
    final OnlineService online = ref.read(onlineProvider);
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.verifyEmailOtp(_email.text.trim(), code);
    if (!mounted) return;
    if (!ok) {
      setState(() { _busy = false; _error = _friendly(online.lastError); });
      return;
    }
    ref.read(settingsProvider).setAuthMode('email');
    if (!mounted) return;
    context.go('/onboarding');
  }

  String _friendly(String? value) {
    if (value == 'network') return context.tx('اتصال اینترنت را بررسی کن.', 'Check your internet connection.');
    if (value == 'invalid login') return context.tx('کد یا ایمیل نادرست است.', 'The email or code is invalid.');
    return context.tx('ارسال یا تأیید کد انجام نشد. دوباره تلاش کن.', 'Could not send or verify the code. Try again.');
  }

  void _continueGuest() {
    ref.read(settingsProvider).setAuthMode('guest');
    final bool hasIdentity = ref.read(profileProvider).hasIdentity;
    context.go(hasIdentity ? '/hub' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Scaffold(
      backgroundColor: visual.background,
      body: NxBrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const OracleAvatar(pose: 'hero_wave', size: 128),
                    const SizedBox(height: 12),
                    Text(context.tx('ورود به NEXORA', 'Sign in to NEXORA'), textAlign: TextAlign.center,
                        style: TextStyle(color: visual.text, fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(context.tx('ابتدا ایمیل واقعی‌ات را تأیید کن؛ سپس وارد حساب می‌شوی.',
                        'Verify your real email first, then enter your account.'), textAlign: TextAlign.center,
                        style: TextStyle(color: visual.muted, height: 1.4)),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: context.tx('ایمیل', 'Email'), prefixIcon: const Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 10),
                    if (_sent) ...<Widget>[
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(labelText: context.tx('کد ارسال‌شده به ایمیل', 'Code sent to your email'), prefixIcon: const Icon(Icons.password_rounded)),
                      ),
                      FilledButton.icon(onPressed: _busy ? null : _verifyCode, icon: const Icon(Icons.verified_rounded), label: Text(context.tx('تأیید و ورود', 'Verify and enter'))),
                      TextButton(onPressed: _busy ? null : _sendCode, child: Text(context.tx('ارسال دوباره کد', 'Resend code'))),
                    ] else
                      FilledButton.icon(onPressed: _busy ? null : _sendCode, icon: const Icon(Icons.mark_email_read_rounded), label: Text(context.tx('ارسال کد به ایمیل', 'Send code to email'))),
                    if (_busy) ...<Widget>[const SizedBox(height: 12), const LinearProgressIndicator()],
                    if (_error != null) ...<Widget>[const SizedBox(height: 10), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontWeight: FontWeight.w700))],
                    const SizedBox(height: 24),
                    OutlinedButton.icon(onPressed: _busy ? null : _continueGuest, icon: const Icon(Icons.offline_bolt_rounded), label: Text(context.tx('ورود مهمان؛ فقط آفلاین', 'Continue as Guest · offline only'))),
                    const SizedBox(height: 8),
                    Text(context.tx('مهمان به حساب آنلاین، چت، بازی آنلاین، تورنمنت و همگام‌سازی دسترسی ندارد.',
                        'Guest mode has no online account, chat, online games, tournaments, or cloud sync.'), textAlign: TextAlign.center,
                        style: TextStyle(color: visual.muted, fontSize: 11, height: 1.35)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
