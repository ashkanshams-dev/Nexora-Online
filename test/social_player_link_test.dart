// Tap-a-player profile, follow, DMs, block: client rules + widgets + the server migration contract.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/assets.dart';
import 'package:nexora/net/supabase.dart';
import 'package:nexora/social/player_link.dart';
import 'package:nexora/social/public_profile.dart';

void main() {
  group('dmBodyError (mirrors the server dm_guard)', () {
    test('empty / whitespace rejected', () {
      expect(dmBodyError(''), isNotNull);
      expect(dmBodyError('   \n '), isNotNull);
    });
    test('limit is $kDmMaxLen characters after trimming', () {
      expect(dmBodyError('سلام'), isNull);
      expect(dmBodyError('  ${'ب' * kDmMaxLen}  '), isNull);
      expect(dmBodyError('ب' * (kDmMaxLen + 1)), contains('طولانی'));
    });
    test('emoji count as one character each', () {
      expect(dmBodyError('⚽' * kDmMaxLen), isNull);
    });
  });

  group('canOpenPlayer', () {
    test('bots, empty seats and myself are not tappable', () {
      expect(canOpenPlayer(null, 'me'), isFalse);
      expect(canOpenPlayer('', 'me'), isFalse);
      expect(canOpenPlayer('bot-1', 'me'), isFalse);
      expect(canOpenPlayer('me', 'me'), isFalse);
      expect(canOpenPlayer('8c1e0f3a-1111-2222-3333-444455556666', 'me'), isTrue);
    });
  });

  group('achievements', () {
    final json = [
      {'id': 'first_win', 'title': 'اولین برد', 'desc': 'd', 'progress': 1, 'target': 1, 'done': true},
      {'id': 'goals_50', 'title': 'گلزن', 'desc': 'd', 'progress': 20, 'target': 50, 'done': false},
      {'id': 'champion', 'title': 'قهرمان', 'desc': 'd', 'progress': 0, 'target': 1, 'done': false},
    ];
    test('parse + progress fraction', () {
      final a = achievementsOf(json);
      expect(a.length, 3);
      expect(a[0].done, isTrue);
      expect(a[1].frac, closeTo(.4, 1e-9));
      expect(a[2].frac, 0);
      expect(achievementsOf(null), isEmpty);
    });
    test('every server achievement id has an existing icon', () {
      const ids = ['first_win', 'wins_10', 'wins_50', 'played_100', 'goals_50', 'goals_200', 'streak_5', 'level_10', 'level_25', 'arena_100', 'champion', 'followers_10', 'unknown_future'];
      for (final id in ids) {
        expect(() => ui2(achievementIcon(id)), returnsNormally, reason: id);
      }
      final sql = File('supabase/migrations/20261115_social_profiles.sql').readAsStringSync();
      for (final id in ids.take(12)) {
        expect(sql.contains("'$id'"), isTrue, reason: 'server defines $id');
      }
    });
    testWidgets('panel shows earned count and titles', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AchievementsPanel(items: achievementsOf(json))))));
      expect(find.text('دستاوردها'), findsOneWidget);
      expect(find.text('۱ از ۳'), findsOneWidget);
      expect(find.text('قهرمان'), findsOneWidget);
    });
  });

  group('PlayerTap', () {
    testWidgets('no tap target for bots / empty seats', (t) async {
      await t.pumpWidget(const Directionality(textDirection: TextDirection.rtl, child: PlayerTap(uid: null, child: Text('ربات'))));
      expect(find.byType(GestureDetector), findsNothing);
      await t.pumpWidget(const Directionality(textDirection: TextDirection.rtl, child: PlayerTap(uid: 'bot-2', child: Text('ربات'))));
      expect(find.byType(GestureDetector), findsNothing);
    });
    testWidgets('real player gets a tap target', (t) async {
      await t.pumpWidget(const Directionality(textDirection: TextDirection.rtl, child: PlayerTap(uid: '8c1e0f3a-1111-2222-3333-444455556666', child: Text('علی'))));
      expect(find.byType(GestureDetector), findsOneWidget);
    });
  });

  testWidgets('UnreadBadge hides at zero and shows Persian count', (t) async {
    DmUnread.i.count.value = 0;
    await t.pumpWidget(const Directionality(textDirection: TextDirection.rtl, child: Center(child: UnreadBadge(child: SizedBox(width: 40, height: 40)))));
    expect(find.text('۰'), findsNothing);
    DmUnread.i.count.value = 3;
    await t.pump();
    expect(find.text('۳'), findsOneWidget);
    DmUnread.i.count.value = 150;
    await t.pump();
    expect(find.text('+۹۹'), findsOneWidget);
    DmUnread.i.count.value = 0;
  });

  test('server errors map to Persian', () {
    expect(errFa(Exception('message too long')), contains('۵۰۰'));
    expect(errFa(Exception('slow down')), contains('صبر'));
    expect(errFa(Exception('unblock first')), contains('مسدودی'));
    expect(errFa(Exception('blocked')), contains('مسدود'));
  });

  test('migration: every RPC is security definer with a fixed search_path and granted only to authenticated', () {
    final sql = File('supabase/migrations/20261115_social_profiles.sql').readAsStringSync();
    const rpcs = ['follow_user', 'unfollow_user', 'block_user', 'unblock_user', 'send_dm', 'dm_unread_total', 'mark_conversation_read', 'player_card', 'player_achievements', 'open_dm'];
    for (final f in rpcs) {
      final m = RegExp('create or replace function public\\.$f\\([^)]*\\)[^\$]*?security definer set search_path = public', dotAll: true).hasMatch(sql);
      expect(m, isTrue, reason: f);
      expect(sql.contains('public.$f('), isTrue);
    }
    expect(sql, contains('from public, anon;'));
    expect(sql, contains('to authenticated;'));
    expect(sql, contains('create trigger dm_guard before insert on public.messages'));
    expect(sql, contains('create trigger follow_guard before insert on public.follows'));
    expect(sql, contains('select $kDmMaxLen'));
  });
}
