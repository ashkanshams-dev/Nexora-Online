/// Supabase e-mail links (sign-up confirmation, magic link, password reset, e-mail change) come back to the app
/// through the custom-scheme deep link `nexora://auth-callback?flow=<flow>&code=<pkce code>`.
///
/// Android registers the scheme/host in the manifest (see .github/workflows/android.yml). Flutter's own deep
/// linking hands the link to GoRouter, which sends it to `/auth/callback` (the in-app page that exchanges the PKCE
/// code for a session). Pure Dart: no Flutter / Supabase imports, so it is unit-tested directly.
library;

/// What the e-mail link was sent for. Carried in our own `flow` query parameter of the redirect URL.
enum AuthLinkFlow { signup, magicLink, recovery, emailChange, unknown }

class AuthLinks {
  const AuthLinks._();

  static const String scheme = 'nexora';
  static const String host = 'auth-callback';

  /// Older builds/apps used the project's site_url `nexora://login-callback`; accepted when parsing.
  static const String legacyHost = 'login-callback';

  /// The in-app route that finishes the sign-in.
  static const String route = '/auth/callback';

  static String flowName(AuthLinkFlow f) => switch (f) {
        AuthLinkFlow.signup => 'signup',
        AuthLinkFlow.magicLink => 'magiclink',
        AuthLinkFlow.recovery => 'recovery',
        AuthLinkFlow.emailChange => 'email_change',
        AuthLinkFlow.unknown => 'unknown',
      };

  static AuthLinkFlow flowFrom(String? v) => switch ((v ?? '').toLowerCase()) {
        'signup' || 'invite' => AuthLinkFlow.signup,
        'magiclink' || 'magic_link' || 'email' => AuthLinkFlow.magicLink,
        'recovery' => AuthLinkFlow.recovery,
        'email_change' => AuthLinkFlow.emailChange,
        _ => AuthLinkFlow.unknown,
      };

  /// `emailRedirectTo` / `redirectTo` passed to Supabase. Must match the project's uri_allow_list
  /// (`nexora://auth-callback**`, also covered by `nexora://**`).
  static String redirectUrl(AuthLinkFlow flow) => '$scheme://$host?flow=${flowName(flow)}';

  /// True when [u] is an auth e-mail callback in any of the shapes Android/Flutter can deliver it:
  /// * full URI `nexora://auth-callback?...` (or the legacy `nexora://login-callback`),
  /// * path-only `/?code=...` / `/auth-callback?...` (older engines pass only path + query),
  /// * the in-app route `/auth/callback?...` itself.
  static bool isCallback(Uri u) {
    if (u.scheme == scheme) return u.host == host || u.host == legacyHost;
    if (u.scheme.isNotEmpty && u.scheme != 'http' && u.scheme != 'https') return false;
    final String p = u.path;
    if (p == '/$host' || p == '/$legacyHost') return true;
    if (p.isEmpty || p == '/') return AuthCallback.fromUri(u).hasPayload;
    return false;
  }

  /// The GoRouter location for a callback link: `/auth/callback?<all parameters>` (fragment params folded in).
  static String routeFor(Uri u) {
    final Map<String, String> q = AuthCallback._params(u);
    return Uri(path: route, queryParameters: q.isEmpty ? null : q).toString();
  }
}

/// Parsed content of a callback link.
class AuthCallback {
  const AuthCallback({
    this.code,
    this.error,
    this.errorCode,
    this.errorDescription,
    this.accessToken,
    this.refreshToken,
    this.flow = AuthLinkFlow.unknown,
  });

  /// PKCE authorization code (exchangeCodeForSession).
  final String? code;
  final String? error;
  final String? errorCode;
  final String? errorDescription;

  /// Implicit-flow tokens (only for links that were not created through PKCE).
  final String? accessToken;
  final String? refreshToken;
  final AuthLinkFlow flow;

  bool get isError => error != null || errorCode != null || errorDescription != null;
  bool get hasCode => code != null;
  bool get hasTokens => refreshToken != null;
  bool get hasPayload => isError || hasCode || hasTokens;

  /// The link expired or was already used (Supabase error_code `otp_expired`).
  bool get isExpired =>
      errorCode == 'otp_expired' || (errorDescription ?? '').toLowerCase().contains('expired');

  static Map<String, String> _params(Uri u) {
    final Map<String, String> q = <String, String>{};
    // Supabase can put errors / implicit tokens in the fragment: '#error=...&error_description=...'.
    final String f = u.fragment;
    if (f.contains('=')) {
      try {
        q.addAll(Uri.splitQueryString(f));
      } catch (_) {}
    }
    q.addAll(u.queryParameters); // query wins over fragment
    return q;
  }

  static String? _v(Map<String, String> q, String k) {
    final String? v = q[k]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  factory AuthCallback.fromUri(Uri u) {
    final Map<String, String> q = _params(u);
    final String? type = _v(q, 'type');
    final AuthLinkFlow flow = AuthLinks.flowFrom(_v(q, 'flow') ?? type);
    return AuthCallback(
      code: _v(q, 'code'),
      error: _v(q, 'error'),
      errorCode: _v(q, 'error_code'),
      errorDescription: _v(q, 'error_description')?.replaceAll('+', ' '),
      accessToken: _v(q, 'access_token'),
      refreshToken: _v(q, 'refresh_token'),
      flow: flow,
    );
  }

  /// Parses a raw string (full deep link or route); invalid input gives an empty callback.
  static AuthCallback parse(String raw) {
    final Uri? u = Uri.tryParse(raw.trim());
    return u == null ? const AuthCallback() : AuthCallback.fromUri(u);
  }
}
