import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/online_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import 'admin_access.dart';

/// Shown (and not dismissible) while the account must change its password — e.g. the default main admin login
/// `admin` / `admin` on first sign-in. Admin RPCs refuse until the password is changed (server side).
class ForcePasswordPage extends ConsumerStatefulWidget {
  const ForcePasswordPage({super.key});

  @override
  ConsumerState<ForcePasswordPage> createState() => _ForcePasswordPageState();
}

class _ForcePasswordPageState extends ConsumerState<ForcePasswordPage> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String? _msg;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String a = _a.text, b = _b.text;
    if (a.length < 6) {
      setState(() => _msg = context.tx('رمز جدید حداقل ۶ کاراکتر', 'At least 6 characters'));
      return;
    }
    if (a != b) {
      setState(() => _msg = context.tx('دو رمز یکی نیستند', 'The passwords do not match'));
      return;
    }
    if (a.toLowerCase() == 'admin') {
      setState(() => _msg = context.tx('رمز پیش‌فرض را دوباره انتخاب نکن', 'Do not reuse the default password'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final OnlineService o = ref.read(onlineProvider);
    final bool ok = await o.changePassword(a);
    await ref.read(adminAccessProvider).refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && !ref.read(adminAccessProvider).mustChangePassword) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tx('رمز عوض شد ✓', 'Password changed ✓'))));
      context.go('/hub');
    } else {
      setState(() => _msg = o.lastError ?? context.tx('تغییر رمز انجام نشد', 'Could not change the password'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final OnlineService o = ref.watch(onlineProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: NxColors.navyDeep,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                const Icon(Icons.lock_reset_rounded, size: 64, color: NxColors.gold),
                const SizedBox(height: 12),
                Text(context.tx('اولین ورود — رمز جدید بگذار', 'First sign-in — set a new password'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                    context.tx('حساب «${o.isInternalAccount ? (o.email ?? '').split('@').first : (o.email ?? '')}» تا رمز را عوض نکنی دسترسی مدیریتی ندارد.',
                        'This account has no admin access until the password is changed.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NxColors.textDim)),
                const SizedBox(height: 20),
                TextField(
                  controller: _a,
                  obscureText: _obscure,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.tx('رمز جدید', 'New password'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _b,
                  obscureText: _obscure,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                      labelText: context.tx('تکرار رمز', 'Repeat password'), prefixIcon: const Icon(Icons.lock_rounded)),
                ),
                if (_msg != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: const TextStyle(color: NxColors.danger))),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: NxColors.gold),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(context.tx('ذخیره', 'Save'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                ),
                TextButton(
                  onPressed: () async {
                    await o.signOut();
                    if (context.mounted) context.go('/hub');
                  },
                  child: Text(context.tx('خروج از این حساب', 'Sign out of this account')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
