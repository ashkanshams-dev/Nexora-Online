import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/cloud_profile_sync.dart';
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
  String? _info;
  int _cooldown = 0;
  Timer? _tick;
  bool _emailPrefillHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_emailPrefillHandled) return;
    _emailPrefillHandled = true;
    _email.text = GoRouterState.of(context).uri.queryParameters['email'] ?? '';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Supabase lets one address request a code once per 60 s (and the built-in mailer only a few per hour), so the
  /// send button counts down instead of firing requests the server will refuse.
  void _startCooldown(int seconds) {
    _tick?.cancel();
    setState(() => _cooldown = seconds);
    if (seconds <= 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
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
    final int wait = online.otpCooldownLeft(email);
    if (wait > 0) {
      _startCooldown(wait);
      setState(() => _error = context.tx('برای ارسال دوباره $wait ثانیه صبر کن.', 'Wait $wait s before requesting another code.'));
      return;
    }
    setState(() { _busy = true; _error = null; _info = null; });
    final bool ok = await online.sendEmailOtp(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _sent = true;
      _error = ok ? null : _friendly(online.lastError, retryAfter: online.lastRetryAfter);
      _info = ok
          ? context.tx(
              'ایمیل ارسال شد. کد را وارد کن. اگر به‌جای کد فقط «لینک ورود» آمد، همان لینک را روی همین گوشی باز کن تا وارد شوی. '
                  'پوشه‌ی اسپم را هم ببین.',
              'Email sent. Enter the code. If the email only has a sign-in link, open that link on this phone to sign in. '
                  'Check your spam folder too.')
          : null;
    });
    if (ok) {
      _startCooldown(OnlineService.otpCooldown.inSeconds);
    } else if (online.lastError == 'rate_limit') {
      _startCooldown(online.lastRetryAfter ?? OnlineService.otpCooldown.inSeconds);
    }
  }

  Future<void> _verifyCode() async {
    final String code = OnlineService.normalizeEmailOtpDigits(_code.text.trim());
    if (!OnlineService.isSixDigitEmailOtp(code)) {
      setState(() => _error = context.tx('کد ۶ رقمی ایمیل را وارد کن.', 'Enter the 6-digit code from the email.'));
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
    ref.read(cloudSyncProvider).start();
    if (!mounted) return;
    context.go(ref.read(profileProvider).hasIdentity ? '/hub' : '/onboarding');
  }

  String _friendly(String? value, {int? retryAfter}) {
    switch (value) {
      case 'network':
        return context.tx('اتصال اینترنت را بررسی کن.', 'Check your internet connection.');
      case 'otp_invalid':
      case 'invalid_login':
        return context.tx('کد نادرست است یا منقضی شده. کد تازه بگیر.', 'The code is wrong or expired. Request a new one.');
      case 'rate_limit':
        final String s = retryAfter != null ? ' ($retryAfter s)' : '';
        return context.tx(
            'سرور فعلاً اجازه‌ی ارسال ایمیل دیگری نمی‌دهد$s. کمی بعد دوباره امتحان کن یا فعلاً مهمان وارد شو.',
            'The server is not allowing another email right now$s. Try again a bit later, or continue as a guest for now.');
      case 'smtp':
        return context.tx('سرور نتوانست ایمیل را بفرستد (تنظیمات ایمیل سرور). فعلاً مهمان وارد شو.',
            'The server could not send the email (server mail settings). Continue as a guest for now.');
      case 'signup_disabled':
        return context.tx('ثبت‌نام حساب تازه روی سرور بسته است.', 'New sign-ups are disabled on the server.');
      case 'not_configured':
        return context.tx('اتصال آنلاین تنظیم نشده است.', 'Online authentication is not configured.');
      case null:
        return context.tx('ارسال یا تأیید کد انجام نشد. دوباره تلاش کن.', 'Could not send or verify the code. Try again.');
      default:
        return context.tx('خطای سرور: $value', 'Server error: $value');
    }
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
                      enabled: !_busy && !_sent,
                      textDirection: TextDirection.ltr,
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
                        textDirection: TextDirection.ltr,
                        autofillHints: const <String>[AutofillHints.oneTimeCode],
                        decoration: InputDecoration(labelText: context.tx('کد ارسال‌شده به ایمیل', 'Code sent to your email'), prefixIcon: const Icon(Icons.password_rounded)),
                      ),
                      FilledButton.icon(onPressed: _busy ? null : _verifyCode, icon: const Icon(Icons.verified_rounded), label: Text(context.tx('تأیید و ورود', 'Verify and enter'))),
                      TextButton(
                          onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                          child: Text(_cooldown > 0
                              ? context.tx('ارسال دوباره کد ($_cooldown)', 'Resend code ($_cooldown)')
                              : context.tx('ارسال دوباره کد', 'Resend code'))),
                      TextButton(
                          onPressed: _busy ? null : () => setState(() { _sent = false; _code.clear(); _error = null; _info = null; }),
                          child: Text(context.tx('تغییر ایمیل', 'Change email'))),
                    ] else
                      FilledButton.icon(
                          onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                          icon: const Icon(Icons.mark_email_read_rounded),
                          label: Text(_cooldown > 0
                              ? context.tx('ارسال کد ($_cooldown)', 'Send code ($_cooldown)')
                              : context.tx('ارسال کد به ایمیل', 'Send code to email'))),
                    if (_info != null) ...<Widget>[const SizedBox(height: 10), Text(_info!, textAlign: TextAlign.center, style: TextStyle(color: visual.muted, fontSize: 12, height: 1.4))],
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
