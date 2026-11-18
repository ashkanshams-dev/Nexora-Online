import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_gateway.dart';
import 'online_config.dart';

/// Initialise Supabase once at startup (no network needed: the session is restored from disk).
Future<void> initOnline() async {
  if (!OnlineConfig.enabled) return;
  try {
    await Supabase.initialize(url: OnlineConfig.supabaseUrl, anonKey: OnlineConfig.supabaseAnonKey);
    OnlineService._ready = true;
    // Second client for the games project: no own auth, it sends the auth project's access token.
    if (OnlineConfig.gamesEnabled) {
      OnlineService._games = SupabaseClient(
        OnlineConfig.gamesUrl,
        OnlineConfig.gamesAnonKey,
        accessToken: () async => Supabase.instance.client.auth.currentSession?.accessToken,
      );
    }
  } catch (e) {
    debugPrint('NEXORA online init failed: $e');
  }
}

/// Auth + connection state for the whole app.
///
/// * Guest = Supabase anonymous user (created silently once the explorer identity exists).
/// * A guest can upgrade to email + password and keeps the same account (same uid, same progress).
/// * Offline / no config: [status] stays [BackendStatus.offline] and every world keeps working locally.
class OnlineService extends ChangeNotifier {
  OnlineService() {
    if (!_ready) return;
    _sub = client!.auth.onAuthStateChange.listen((AuthState s) {
      _status = s.session != null ? BackendStatus.online : BackendStatus.offline;
      final String? tok = s.session?.accessToken;
      if (_games != null) unawaited(_games!.realtime.setAuth(tok));
      if (s.session != null &&
          (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession ||
              s.event == AuthChangeEvent.userUpdated)) {
        unawaited(gamesHello());
      }
      notifyListeners();
    }, onError: (Object e) => debugPrint('auth stream: $e'));
    if (client!.auth.currentSession != null) _status = BackendStatus.online;
  }

  static bool _ready = false;
  static SupabaseClient? _games;
  String? _helloFor;

  /// Games project client (rooms, matches, matchmaking, tournaments, leaderboards). Falls back to the auth client
  /// in builds without the games config so offline/dev builds keep working.
  SupabaseClient? get games => _ready ? (_games ?? Supabase.instance.client) : null;

  /// Registers this player on the games project (creates the profile mirror row, asks for a fresh wallet snapshot).
  /// Every games RPC needs the mirror row; called after each sign-in and before entering lobbies/tournaments.
  Future<void> gamesHello({bool force = false}) async {
    final SupabaseClient? g = _games;
    final String? id = uid;
    if (g == null || id == null || (!force && _helloFor == id)) return;
    try {
      await g.rpc('nx_g_hello');
      _helloFor = id;
    } catch (e) {
      debugPrint('games hello: $e');
    }
  }
  StreamSubscription<AuthState>? _sub;
  BackendStatus _status = BackendStatus.offline;
  String? lastError;
  bool busy = false;

  bool get configured => _ready;
  SupabaseClient? get client => _ready ? Supabase.instance.client : null;
  BackendStatus get status => _status;
  bool get isOnline => _status == BackendStatus.online && user != null;
  User? get user => client?.auth.currentUser;
  String? get uid => user?.id;
  bool get isGuest => user?.isAnonymous ?? true;
  String? get email => user?.email;

  /// Returns the existing authenticated session. Guest mode is local-only;
  /// this method never creates a Supabase anonymous account.
  Future<bool> ensureSession() async {
    final SupabaseClient? c = client;
    if (c == null) return false;
    if (c.auth.currentSession != null) {
      _status = BackendStatus.online;
      return true;
    }
    _status = BackendStatus.offline;
    lastError = 'email_login_required';
    notifyListeners();
    return false;
  }

  /// Deep link the e-mail's sign-in link opens (Android intent filter `nexora://login-callback`, added by CI).
  /// supabase_flutter exchanges the `?code=` itself, so a user whose e-mail carries only a link (no 6-digit code,
  /// e.g. while the project's Magic Link template lacks `{{ .Token }}`) can still sign in by tapping it on this phone.
  /// The URL must be in Supabase → Authentication → URL Configuration → Redirect URLs, otherwise the server falls
  /// back to the project's Site URL.
  static const String emailRedirect = 'nexora://login-callback';

  /// Last time a code was requested per e-mail (Supabase allows one request per address every 60 s).
  static final Map<String, DateTime> _otpSentAt = <String, DateTime>{};
  static const Duration otpCooldown = Duration(seconds: 60);

  /// Only send metadata accepted by the shared profiles.username constraint.
  /// Null lets the database trigger generate its safe default username.
  static String? signupUsername(String? username) {
    final String candidate = username?.trim() ?? '';
    final int length = candidate.runes.length;
    return length >= 3 && length <= 20 ? candidate : null;
  }

  static String normalizeEmailOtpDigits(String value) {
    const String fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    final StringBuffer b = StringBuffer();
    for (final int r in value.runes) {
      final String ch = String.fromCharCode(r);
      final int i = fa.indexOf(ch), j = ar.indexOf(ch);
      if (i >= 0) {
        b.write(i);
      } else if (j >= 0) {
        b.write(j);
      } else if (ch.trim().isNotEmpty) {
        b.write(ch);
      }
    }
    return b.toString();
  }

  static bool isSixDigitEmailOtp(String value) => RegExp(r'^\d{6}$').hasMatch(value);

  /// Seconds until another code may be requested for [email] (0 = now).
  int otpCooldownLeft(String email) {
    final DateTime? at = _otpSentAt[email.trim().toLowerCase()];
    if (at == null) return 0;
    final int left = otpCooldown.inSeconds - DateTime.now().difference(at).inSeconds;
    return left > 0 ? left : 0;
  }

  /// Seconds the server asked us to wait (parsed from its rate-limit message), if any.
  int? lastRetryAfter;

  Future<bool> sendEmailOtp(String email) async {
    final String e = email.trim();
    lastRetryAfter = null;
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.signInWithOtp(email: e, shouldCreateUser: true, emailRedirectTo: emailRedirect);
      return true;
    });
    if (ok == true) _otpSentAt[e.toLowerCase()] = DateTime.now();
    return ok ?? false;
  }

  Future<bool> verifyEmailOtp(String email, String token) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.verifyOTP(email: email.trim(), token: token.trim(), type: OtpType.email);
      return c.auth.currentSession != null;
    });
    return ok ?? false;
  }

  /// Normalised error keys for the UI (see AuthPage): network, rate_limit, otp_invalid, smtp, signup_disabled,
  /// invalid_login, email_taken, weak_password, or the server message.
  String _friendly(Object e) {
    if (e is AuthException) {
      final String m = e.message.toLowerCase();
      final String code = (e.code ?? '').toLowerCase();
      if (e.statusCode == '429' || code.contains('rate_limit') || m.contains('rate limit') ||
          m.contains('security purposes') || m.contains('too many')) {
        final RegExpMatch? s = RegExp(r'after (\d+) second').firstMatch(m);
        lastRetryAfter = s != null ? int.tryParse(s.group(1)!) : null;
        return 'rate_limit';
      }
      if (code == 'otp_expired' || m.contains('token has expired') || (m.contains('otp') && m.contains('invalid'))) {
        return 'otp_invalid';
      }
      if (code == 'email_address_not_authorized' || m.contains('not authorized') || m.contains('error sending') ||
          m.contains('smtp')) {
        return 'smtp';
      }
      if (code == 'signup_disabled' || m.contains('signups not allowed')) return 'signup_disabled';
      if (code == 'invalid_credentials' || m.contains('invalid login')) return 'invalid_login';
      if (m.contains('already') || m.contains('registered')) return 'email_taken';
      if (m.contains('password')) return 'weak_password';
      return e.message;
    }
    final String s = '$e';
    if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException') ||
        s.contains('TimeoutException')) {
      return 'network';
    }
    return s;
  }

  Future<T?> _run<T>(Future<T> Function(SupabaseClient c) f) async {
    final SupabaseClient? c = client;
    if (c == null) {
      lastError = 'not_configured';
      return null;
    }
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final T r = await f(c);
      return r;
    } catch (e) {
      lastError = _friendly(e);
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Guest → permanent account (same uid, all progress kept). Without a guest: new account.
  Future<bool> registerEmail(String email, String password, {String? username}) async {
    final String? safeUsername = signupUsername(username);
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      final User? u = c.auth.currentUser;
      if (u != null && u.isAnonymous) {
        await c.auth.updateUser(UserAttributes(email: email.trim(), password: password));
      } else {
        await c.auth.signUp(
          email: email.trim(),
          password: password,
          data: safeUsername == null ? null : <String, dynamic>{'username': safeUsername},
        );
      }
      return true;
    });
    return ok ?? false;
  }

  /// Username logins (no «@», e.g. the default main admin `admin`) map to an internal e-mail that never receives mail.
  /// Their stored password is the typed one with a fixed prefix, so short admin passwords still satisfy the project's
  /// 6-character minimum for real e-mail accounts (which is unchanged).
  static const String internalDomain = 'users.nexora.invalid';
  static bool isUsernameLogin(String id) => !id.trim().contains('@');
  static String loginEmail(String id) =>
      isUsernameLogin(id) ? '${id.trim().toLowerCase()}@$internalDomain' : id.trim();
  static String loginPassword(String id, String password) => isUsernameLogin(id) ? 'nx#$password' : password;
  bool get isInternalAccount => (email ?? '').endsWith('@$internalDomain');

  Future<bool> signInEmail(String email, String password) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.signInWithPassword(email: loginEmail(email), password: loginPassword(email, password));
      return true;
    });
    return ok ?? false;
  }

  /// Change the signed-in account's password (same prefix rule for username accounts), then refresh the token so the
  /// server-side "must change password" flag (cleared by a trigger on the password change) leaves the JWT claims too.
  Future<bool> changePassword(String newPassword) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      final String pw = isInternalAccount ? 'nx#$newPassword' : newPassword;
      await c.auth.updateUser(UserAttributes(password: pw));
      await c.auth.refreshSession();
      return true;
    });
    return ok ?? false;
  }

  Future<bool> resetPassword(String email) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.resetPasswordForEmail(email.trim());
      return true;
    });
    return ok ?? false;
  }

  /// Sign out. Guest mode is local-only and never creates an anonymous session.
  Future<void> signOut({bool continueAsGuest = false}) async {
    await _run<bool>((SupabaseClient c) async {
      await c.auth.signOut();
      return true;
    });
    if (continueAsGuest) await ensureSession();
  }

  /// RPC on the games project.
  Future<dynamic> grpc(String fn, [Map<String, dynamic>? params]) async {
    final SupabaseClient? g = games;
    if (g == null || client?.auth.currentSession == null) return null;
    await gamesHello();
    return g.rpc(fn, params: params);
  }

  /// Small helper for RPC calls that should never throw into the UI.
  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) async {
    final SupabaseClient? c = client;
    if (c == null || c.auth.currentSession == null) return null;
    return c.rpc(fn, params: params);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final onlineProvider = ChangeNotifierProvider<OnlineService>((ref) => OnlineService());
