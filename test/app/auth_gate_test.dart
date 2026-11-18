import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/auth_gate.dart';

void main() {
  test('access comes from the real session first, then the guest choice', () {
    expect(nxAccess(authMode: '', hasUser: false, anonymous: true), NxAccess.needsAuth);
    expect(nxAccess(authMode: 'guest', hasUser: false, anonymous: true), NxAccess.guest);
    expect(nxAccess(authMode: 'email', hasUser: false, anonymous: true), NxAccess.needsAuth, reason: 'signed out');
    // A guest who signs in from Account (password / admin login) is signed in even though authMode is still guest.
    expect(nxAccess(authMode: 'guest', hasUser: true, anonymous: false), NxAccess.signedIn);
    expect(nxAccess(authMode: '', hasUser: true, anonymous: false), NxAccess.signedIn, reason: 'magic link');
    expect(nxAccess(authMode: '', hasUser: true, anonymous: true), NxAccess.needsAuth, reason: 'anonymous user');
  });

  test('guests get the sign-in screen for online-only routes instead of a second /hub', () {
    for (final String p in <String>['/social', '/world/orbit_network', '/world/social_station', '/world/nova_gallery',
      '/leaderboard', '/tournaments', '/tournaments/abc', '/online/finger_soccer', '/call/x']) {
      final String? r = authRedirect(Uri.parse(p), NxAccess.guest, hasIdentity: true);
      expect(r, startsWith(kSignInRequiredPath), reason: p);
      expect(Uri.parse(r!).queryParameters['from'], p);
    }
    for (final String p in <String>['/hub', '/rooms', '/world/nexora_arcade', '/arcade/pool8', '/settings', '/account',
      '/oracle', '/rewards', '/world/personal_orbit', '/world/nexora_exchange']) {
      expect(authRedirect(Uri.parse(p), NxAccess.guest, hasIdentity: true), isNull, reason: p);
    }
  });

  test('signed-in users reach every route and leave /auth', () {
    for (final String p in <String>['/social', '/world/orbit_network', '/rooms', '/online/pool8', '/tournaments']) {
      expect(authRedirect(Uri.parse(p), NxAccess.signedIn, hasIdentity: true), isNull, reason: p);
    }
    expect(authRedirect(Uri.parse('/auth'), NxAccess.signedIn, hasIdentity: true), '/hub');
    expect(authRedirect(Uri.parse('/auth'), NxAccess.signedIn, hasIdentity: false), '/onboarding');
  });

  test('no session and no guest choice -> /auth (intro may still play)', () {
    expect(authRedirect(Uri.parse('/hub'), NxAccess.needsAuth, hasIdentity: true), '/auth');
    expect(authRedirect(Uri.parse('/auth'), NxAccess.needsAuth, hasIdentity: true), isNull);
    expect(authRedirect(Uri.parse('/intro?next=/auth'), NxAccess.needsAuth, hasIdentity: false), isNull);
  });
}
