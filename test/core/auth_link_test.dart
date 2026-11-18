import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/auth_link.dart';

void main() {
  group('AuthLinks.redirectUrl', () {
    test('custom scheme with flow', () {
      expect(AuthLinks.redirectUrl(AuthLinkFlow.signup), 'nexora://auth-callback?flow=signup');
      expect(AuthLinks.redirectUrl(AuthLinkFlow.recovery), 'nexora://auth-callback?flow=recovery');
      expect(AuthLinks.redirectUrl(AuthLinkFlow.magicLink), 'nexora://auth-callback?flow=magiclink');
      expect(AuthLinks.redirectUrl(AuthLinkFlow.emailChange), 'nexora://auth-callback?flow=email_change');
    });
    test('round trips the flow', () {
      for (final AuthLinkFlow f in AuthLinkFlow.values.where((AuthLinkFlow f) => f != AuthLinkFlow.unknown)) {
        expect(AuthCallback.parse(AuthLinks.redirectUrl(f)).flow, f);
      }
    });
  });

  group('AuthLinks.isCallback', () {
    test('full deep link', () {
      expect(AuthLinks.isCallback(Uri.parse('nexora://auth-callback?flow=signup&code=abc')), isTrue);
      expect(AuthLinks.isCallback(Uri.parse('nexora://login-callback?code=abc')), isTrue);
    });
    test('path-only deliveries', () {
      expect(AuthLinks.isCallback(Uri.parse('/?code=abc')), isTrue);
      expect(AuthLinks.isCallback(Uri.parse('/?error=access_denied&error_code=otp_expired')), isTrue);
      expect(AuthLinks.isCallback(Uri.parse('/auth-callback?flow=signup&code=abc')), isTrue);
    });
    test('other links are not callbacks', () {
      expect(AuthLinks.isCallback(Uri.parse('nexora://t/ABCD2345')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('/ABCD2345')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('/hub')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('/')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('/intro?next=%2Fhub')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('/online/ludo?code=XY12')), isFalse);
      expect(AuthLinks.isCallback(Uri.parse('mailto:a@b.c')), isFalse);
    });
  });

  group('AuthLinks.routeFor', () {
    test('keeps every parameter on the in-app route', () {
      final Uri r = Uri.parse(AuthLinks.routeFor(Uri.parse('nexora://auth-callback?flow=signup&code=abc-123')));
      expect(r.path, '/auth/callback');
      expect(r.queryParameters, <String, String>{'flow': 'signup', 'code': 'abc-123'});
    });
    test('folds fragment errors into the query', () {
      final Uri r = Uri.parse(AuthLinks.routeFor(Uri.parse(
          'nexora://auth-callback?flow=signup#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired')));
      expect(r.path, '/auth/callback');
      expect(r.queryParameters['error_code'], 'otp_expired');
      expect(r.queryParameters['flow'], 'signup');
      expect(AuthCallback.fromUri(r).isExpired, isTrue);
    });
  });

  group('AuthCallback.parse', () {
    test('PKCE code', () {
      final AuthCallback c = AuthCallback.parse('nexora://auth-callback?flow=signup&code=8a1b2c');
      expect(c.code, '8a1b2c');
      expect(c.flow, AuthLinkFlow.signup);
      expect(c.isError, isFalse);
      expect(c.hasPayload, isTrue);
    });
    test('error in query', () {
      final AuthCallback c = AuthCallback.parse(
          'nexora://auth-callback?error=server_error&error_code=unexpected_failure&error_description=Database%20error');
      expect(c.isError, isTrue);
      expect(c.isExpired, isFalse);
      expect(c.errorDescription, 'Database error');
      expect(c.code, isNull);
    });
    test('implicit tokens in fragment', () {
      final AuthCallback c =
          AuthCallback.parse('nexora://login-callback#access_token=at&refresh_token=rt&type=recovery&expires_in=3600');
      expect(c.accessToken, 'at');
      expect(c.refreshToken, 'rt');
      expect(c.hasTokens, isTrue);
      expect(c.flow, AuthLinkFlow.recovery);
    });
    test('our flow wins over supabase type', () {
      expect(AuthCallback.parse('nexora://auth-callback?flow=magiclink&type=signup&code=x').flow, AuthLinkFlow.magicLink);
    });
    test('empty / garbage', () {
      expect(AuthCallback.parse('nexora://auth-callback').hasPayload, isFalse);
      expect(AuthCallback.parse('nexora://auth-callback?code=').hasCode, isFalse);
      expect(AuthCallback.parse('::::').hasPayload, isFalse);
      expect(AuthCallback.parse('').flow, AuthLinkFlow.unknown);
    });
  });
}
