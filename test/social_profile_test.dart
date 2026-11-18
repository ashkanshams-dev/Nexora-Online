import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/social_station/data/social_profile_repository.dart';

void main() {
  test('SocialProfile keeps server identity and follow state', () {
    final SocialProfile p = SocialProfile.fromJson(<String, dynamic>{
      'id': 'user-b', 'username': 'beta', 'display_name': 'Beta', 'followers': 12,
      'following': 4, 'posts': 3, 'is_following': true, 'is_pending': false,
    });
    expect(p.id, 'user-b');
    expect(p.username, 'beta');
    expect(p.followers, 12);
    expect(p.isFollowing, isTrue);
    expect(p.isPending, isFalse);
  });

  test('SocialMessage parses UTC timestamp and sender', () {
    final SocialMessage m = SocialMessage.fromJson(<String, dynamic>{
      'id': 'm1', 'author': 'user-a', 'text': 'hello', 'created_at': '2026-11-18T12:00:00Z',
    });
    expect(m.author, 'user-a');
    expect(m.text, 'hello');
    expect(m.createdAt.toUtc().year, 2026);
  });
}
