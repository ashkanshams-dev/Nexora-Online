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
  @override ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _sent = false, _busy = false, _passwordMode = true, _forgotMode = false;
  String? _error;
  @override void dispose() { _email.dispose(); _code.dispose(); _password.dispose(); super.dispose(); }
  String _friendly(String? value) {
    if (value == 'network') return context.tx('اتصال اینترنت را بررسی کن.', 'Check your internet connection.');
    if (value == 'invalid login' || value == 'invalid_login') return context.tx('ایمیل یا رمز نادرست است.', 'The email or password is invalid.');
    if (value == 'weak_password') return context.tx('رمز عبور باید حداقل ۶ کاراکتر باشد.', 'Password must contain at least 6 characters.');
    return context.tx('عملیات احراز هویت انجام نشد. دوباره تلاش کن.', 'Authentication failed. Try again.');
  }
  Future<void> _passwordLogin() async {
    final String email = _email.text.trim(), password = _password.text;
    if (!email.contains('@') || password.length < 6) { setState(() => _error = context.tx('ایمیل و رمز معتبر وارد کن.', 'Enter a valid email and password.')); return; }
    final OnlineService online = ref.read(onlineProvider);
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.signInEmail(email, password);
    if (!mounted) return;
    setState(() { _busy = false; _error = ok ? null : _friendly(online.lastError); });
    if (ok) context.go('/hub');
  }
  Future<void> _forgotPassword() async {
    final String email = _email.text.trim();
    if (!email.contains('@')) { setState(() => _error = context.tx('ابتدا ایمیل را وارد کن.', 'Enter your email first.')); return; }
    final OnlineService online = ref.read(onlineProvider);
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.resetPassword(email);
    if (!mounted) return;
    setState(() { _busy = false; _error = ok ? context.tx('لینک بازیابی رمز به ایمیل ارسال شد.', 'Password reset link sent to your email.') : _friendly(online.lastError); });
  }
  Future<void> _sendCode() async {
    final String email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) { setState(() => _error = context.tx('ایمیل معتبر وارد کن.', 'Enter a valid email address.')); return; }
    final OnlineService online = ref.read(onlineProvider);
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.sendEmailOtp(email);
    if (!mounted) return;
    setState(() { _busy = false; _sent = ok; _error = ok ? null : _friendly(online.lastError); });
  }
  Future<void> _verifyCode() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) { setState(() => _error = context.tx('کد باید ۶ رقم باشد.', 'The code must be 6 digits.')); return; }
    final OnlineService online = ref.read(onlineProvider);
    setState(() { _busy = true; _error = null; });
    final bool ok = await online.verifyEmailOtp(_email.text.trim(), _code.text.trim());
    if (!mounted) return;
    if (!ok) { setState(() { _busy = false; _error = _friendly(online.lastError); }); return; }
    ref.read(settingsProvider).setAuthMode('email');
    context.go('/onboarding');
  }
  void _continueGuest() { ref.read(settingsProvider).setAuthMode('guest'); context.go(ref.read(profileProvider).hasIdentity ? '/hub' : '/onboarding'); }

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final List<Widget> authFields = <Widget>[
      TextField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: context.tx('ایمیل', 'Email'), prefixIcon: const Icon(Icons.email_outlined))),
      const SizedBox(height: 10),
    ];
    if (_passwordMode) {
      authFields.add(TextField(controller: _password, enabled: !_busy, obscureText: true, decoration: InputDecoration(labelText: context.tx('رمز عبور', 'Password'), prefixIcon: const Icon(Icons.lock_outline_rounded))));
      authFields.add(const SizedBox(height: 10));
      authFields.add(_forgotMode ? OutlinedButton.icon(onPressed: _busy ? null : _forgotPassword, icon: const Icon(Icons.mark_email_read_outlined), label: Text(context.tx('ارسال لینک بازیابی', 'Send reset link'))) : FilledButton.icon(onPressed: _busy ? null : _passwordLogin, icon: const Icon(Icons.login_rounded), label: Text(context.tx('ورود با رمز', 'Sign in with password'))));
      authFields.add(TextButton(onPressed: _busy ? null : () => setState(() => _forgotMode = !_forgotMode), child: Text(_forgotMode ? context.tx('بازگشت به ورود', 'Back to sign in') : context.tx('رمز عبور را فراموش کرده‌ام', 'Forgot password'))));
    } else {
      if (_sent) {
        authFields.add(TextField(controller: _code, enabled: !_busy, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, decoration: InputDecoration(labelText: context.tx('کد ایمیل', 'Email code'), prefixIcon: const Icon(Icons.password_rounded))));
        authFields.add(FilledButton.icon(onPressed: _busy ? null : _verifyCode, icon: const Icon(Icons.verified_rounded), label: Text(context.tx('تأیید و ورود', 'Verify and enter'))));
        authFields.add(TextButton(onPressed: _busy ? null : _sendCode, child: Text(context.tx('ارسال دوباره کد', 'Resend code'))));
      } else {
        authFields.add(FilledButton.icon(onPressed: _busy ? null : _sendCode, icon: const Icon(Icons.mark_email_read_rounded), label: Text(context.tx('ارسال کد به ایمیل', 'Send code to email'))));
      }
    }
    authFields.add(TextButton(onPressed: _busy ? null : () => setState(() { _passwordMode = !_passwordMode; _forgotMode = false; }), child: Text(_passwordMode ? context.tx('ورود با کد یک‌بارمصرف', 'Use email one-time code') : context.tx('ورود با رمز عبور', 'Use password sign in'))));
    if (_busy) authFields.addAll(<Widget>[const SizedBox(height: 12), const LinearProgressIndicator()]);
    if (_error != null) authFields.addAll(<Widget>[const SizedBox(height: 10), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontWeight: FontWeight.w700))]);
    authFields.addAll(<Widget>[const SizedBox(height: 24), OutlinedButton.icon(onPressed: _busy ? null : _continueGuest, icon: const Icon(Icons.offline_bolt_rounded), label: Text(context.tx('ورود مهمان؛ فقط آفلاین', 'Continue as Guest · offline only')))]);
    return Scaffold(backgroundColor: visual.background, body: NxBrandBackground(child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const OracleAvatar(pose: 'hero_wave', size: 128), const SizedBox(height: 12),
      Text(context.tx('ورود به NEXORA', 'Sign in to NEXORA'), textAlign: TextAlign.center, style: TextStyle(color: visual.text, fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8), Text(context.tx('ورود واقعی با Supabase؛ حساب و داده‌ها دائمی هستند.', 'Real Supabase authentication with durable account data.'), textAlign: TextAlign.center, style: TextStyle(color: visual.muted, height: 1.4)),
      const SizedBox(height: 22), ...authFields,
    ])))))));
  }
}
