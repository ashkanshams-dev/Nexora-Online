// Auth + online profile — port of src/net/auth.tsx.
// Guests are signed in anonymously on demand; e-mail sign-up / sign-in / reset; guest → e-mail upgrade keeps
// the same user id; the user's own profiles row is kept live with a Realtime postgres_changes subscription.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

const authRedirect = 'nexora://auth';

typedef Res = ({bool ok, String? info, String? error});
Res okR([String? info]) => (ok: true, info: info, error: null);
Res errR(String e) => (ok: false, info: null, error: e);

class Auth extends ChangeNotifier {
  Auth._();
  static final Auth I = Auth._();

  bool ready = false, recovery = false;
  Session? session;
  JRow? profile;
  RealtimeChannel? _ch;
  StreamSubscription<AuthState>? _sub;
  Future<String?>? _ensuring;
  void Function(String m, [String k])? toast;

  bool get configured => ONLINE_CONFIGURED;
  String? get uid => session?.user.id;
  String? get email => session?.user.email;
  bool get isGuest => session != null && (session!.user.isAnonymous || (session!.user.email ?? '').isEmpty);

  Future<void> init() async {
    if (!ONLINE_CONFIGURED) {
      ready = true;
      notifyListeners();
      return;
    }
    session = supabase.auth.currentSession;
    ready = true;
    _sub = supabase.auth.onAuthStateChange.listen((s) {
      final prev = uid;
      session = s.session;
      if (s.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (s.event == AuthChangeEvent.signedOut) profile = null;
      if (prev != uid) _watchProfile();
      notifyListeners();
    });
    _watchProfile();
    notifyListeners();
  }

  /// e-mail links (nexora://auth#access_token=…)
  Future<void> handleLink(Uri uri) async {
    final raw = uri.fragment.isNotEmpty ? uri.fragment : uri.query;
    final q = Uri.splitQueryString(raw);
    if (q['error_description'] != null || q['error'] != null) {
      toast?.call(q['error_code'] == 'otp_expired' ? 'لینک ایمیل منقضی شده؛ دوباره درخواست بده' : errFa(q['error_description'] ?? q['error']), 'err');
      return;
    }
    try {
      await supabase.auth.getSessionFromUrl(uri);
      if (q['type'] == 'recovery') {
        recovery = true;
        notifyListeners();
      } else {
        toast?.call(q['type'] == 'email_change' ? 'ایمیل تأیید شد' : 'حسابت تأیید شد · خوش اومدی!', 'ok');
      }
    } catch (e) {
      toast?.call(errFa(e), 'err');
    }
  }

  void _watchProfile() {
    if (_ch != null) {
      supabase.removeChannel(_ch!);
      _ch = null;
    }
    final id = uid;
    if (id == null) {
      profile = null;
      notifyListeners();
      return;
    }
    supabase.from('profiles').select().eq('id', id).maybeSingle().then((d) {
      if (d != null) {
        profile = d;
        notifyListeners();
      }
    }).catchError((_) {});
    supabase.from('profiles').update({'online_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).then((_) {}).catchError((_) {});
    _ch = supabase
        .channel('profile:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (pl) {
            profile = {...?profile, ...pl.newRecord};
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<JRow?> refreshProfile() async {
    final id = uid;
    if (id == null) return null;
    try {
      profile = await supabase.from('profiles').select().eq('id', id).maybeSingle();
      notifyListeners();
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<String?> ensure() async {
    if (!ONLINE_CONFIGURED) return null;
    final s = supabase.auth.currentSession;
    if (s != null) return s.user.id;
    return _ensuring ??= () async {
      try {
        final r = await supabase.auth.signInAnonymously();
        return r.user?.id;
      } finally {
        _ensuring = null;
      }
    }();
  }

  Future<Res> _wrap(Future<Res> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      return errR(errFa(e));
    }
  }

  Future<Res> signUp(String email, String password) => _wrap(() async {
        final r = await supabase.auth.signUp(email: email.trim(), password: password, emailRedirectTo: authRedirect);
        return r.session == null ? okR('confirm') : okR();
      });
  Future<Res> signIn(String email, String password) => _wrap(() async {
        await supabase.auth.signInWithPassword(email: email.trim(), password: password);
        return okR();
      });
  Future<Res> upgrade(String email, String password) => _wrap(() async {
        await supabase.auth.updateUser(UserAttributes(email: email.trim(), password: password), emailRedirectTo: authRedirect);
        return okR('confirm');
      });
  Future<Res> resetPassword(String email) => _wrap(() async {
        await supabase.auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirect);
        return okR();
      });
  Future<Res> setNewPassword(String password) => _wrap(() async {
        await supabase.auth.updateUser(UserAttributes(password: password));
        recovery = false;
        notifyListeners();
        return okR();
      });
  Future<Res> resend(String email) => _wrap(() async {
        await supabase.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: authRedirect);
        return okR();
      });
  Future<void> signOut() async {
    try {
      await supabase.rpc('leave_all_rooms');
    } catch (_) {}
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    profile = null;
    notifyListeners();
  }

  Future<Res> setUsername(String name) => _wrap(() async {
        final n = name.trim();
        if (n.length < 3 || n.length > 20) return errR('نام کاربری باید ۳ تا ۲۰ کاراکتر باشد');
        if (!RegExp(r'^[A-Za-z0-9_.\- \u0600-\u06FF\u200c]+$').hasMatch(n)) return errR('فقط حروف، عدد، فاصله و _ . - مجاز است');
        final id = uid;
        if (id == null) return errR('اول وارد حساب شو');
        await supabase.from('profiles').update({'username': n}).eq('id', id);
        if (profile != null) profile = {...profile!, 'username': n};
        notifyListeners();
        return okR();
      });

  void endRecovery() {
    recovery = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
