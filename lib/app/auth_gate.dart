/// Who is using the app right now, derived from the real auth session (not only from the saved auth mode).
///
/// * [signedIn]: a non-anonymous Supabase session exists (email OTP, magic link, password or admin login).
/// * [guest]: the user picked "Continue as guest" on the sign-in page and has no session (local-only play).
/// * [needsAuth]: neither; the sign-in page is shown.
enum NxAccess { needsAuth, guest, signedIn }

NxAccess nxAccess({required String authMode, required bool hasUser, required bool anonymous}) {
  if (hasUser && !anonymous) return NxAccess.signedIn;
  if (authMode == 'guest') return NxAccess.guest;
  return NxAccess.needsAuth;
}

/// Screens that only work with an online account. Guests get a clear "sign in required" screen for them instead of
/// being bounced silently (the old redirect to /hub pushed a second home page on top of the first one, so the dock's
/// chat/tournament buttons looked dead and Back led to the same menu again).
///
/// `/rooms` is NOT here: it is the dock's GAME button and already offers the offline "All games" entry.
bool isOnlineOnlyPath(String path) =>
    path == '/social' ||
    path == '/leaderboard' ||
    path.startsWith('/online/') ||
    path.startsWith('/call/') ||
    path == '/tournaments' ||
    path.startsWith('/tournaments/') ||
    path.startsWith('/t/') ||
    path == '/world/orbit_network' ||
    path == '/world/social_station' ||
    path == '/world/nova_gallery';

const String kSignInRequiredPath = '/signin-required';

/// The auth part of the router redirect (pure, so it is unit-tested). Returns null to stay.
String? authRedirect(Uri u, NxAccess access, {required bool hasIdentity}) {
  final String path = u.path;
  switch (access) {
    case NxAccess.needsAuth:
      // The launch intro may still play; it continues to /auth by itself.
      if (path == '/auth' || path == '/intro') return null;
      return '/auth';
    case NxAccess.signedIn:
      // A session can appear while the sign-in page is open (magic-link deep link, OTP from another tab).
      if (path == '/auth' || path == kSignInRequiredPath) return hasIdentity ? '/hub' : '/onboarding';
      return null;
    case NxAccess.guest:
      if (isOnlineOnlyPath(path)) {
        return Uri(path: kSignInRequiredPath, queryParameters: <String, String>{'from': path}).toString();
      }
      return null;
  }
}
