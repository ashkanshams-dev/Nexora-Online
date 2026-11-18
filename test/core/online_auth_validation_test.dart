import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/online/online_service.dart';

void main() {
  group('signup username metadata', () {
    test('omits names shorter than the shared database minimum', () {
      expect(OnlineService.signupUsername('ir'), isNull);
      expect(OnlineService.signupUsername('  ab  '), isNull);
      expect(OnlineService.signupUsername(''), isNull);
      expect(OnlineService.signupUsername(null), isNull);
    });

    test('trims and preserves usernames within the database range', () {
      expect(OnlineService.signupUsername('  explorer  '), 'explorer');
      expect(OnlineService.signupUsername('abc'), 'abc');
      expect(OnlineService.signupUsername('x' * 20), 'x' * 20);
      expect(OnlineService.signupUsername('x' * 21), isNull);
    });
  });

  group('email OTP validation', () {
    test('normalizes Persian and Arabic numerals', () {
      expect(OnlineService.normalizeEmailOtpDigits('۱۲۳۴۵۶'), '123456');
      expect(OnlineService.normalizeEmailOtpDigits('١٢٣٤٥٦'), '123456');
    });

    test('accepts exactly six digits and rejects all other lengths', () {
      expect(OnlineService.isSixDigitEmailOtp('123456'), isTrue);
      expect(OnlineService.isSixDigitEmailOtp('12345'), isFalse);
      expect(OnlineService.isSixDigitEmailOtp('1234567'), isFalse);
      expect(OnlineService.isSixDigitEmailOtp('12a456'), isFalse);
    });
  });
}
