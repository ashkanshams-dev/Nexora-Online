// Local notifications + alarms (flutter_local_notifications) and Firebase Cloud Messaging push.
//  local: daily reward ready, daily challenges refresh / unclaimed, tournament start reminders, match found (app in
//         background), and in-app notifications while backgrounded.
//  push : FCM token → register_device RPC; server trigger → push-send edge function. Firebase is optional: without a
//         configured Firebase app (google-services / FirebaseOptions) everything degrades to local-only, silently.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'supabase.dart';

/// optional Firebase options injected at build time (--dart-define=FCM_API_KEY=… etc.); empty → use google-services.json if present
const _fApiKey = String.fromEnvironment('FCM_API_KEY');
const _fAppId = String.fromEnvironment('FCM_APP_ID');
const _fSender = String.fromEnvironment('FCM_SENDER_ID');
const _fProject = String.fromEnvironment('FCM_PROJECT_ID');

const _channels = [
  ('general', 'NEXORA', 'اعلان‌های عمومی'),
  ('messages', 'پیام‌ها', 'پیام‌های خصوصی'),
  ('social', 'اجتماعی', 'دوستان، دنبال‌کننده‌ها و باشگاه'),
  ('matches', 'مسابقه', 'پیدا شدن حریف و دعوت به بازی'),
  ('rewards', 'جایزه‌ها', 'جایزه‌ی روزانه و چالش‌ها'),
  ('tournaments', 'تورنمنت', 'یادآور شروع تورنمنت'),
];

class NotifTap {
  final String? kind;
  final Map<String, dynamic> data;
  const NotifTap(this.kind, this.data);
}

class LocalNotify with WidgetsBindingObserver {
  LocalNotify._();
  static final LocalNotify I = LocalNotify._();

  final _p = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<NotifTap>.broadcast();
  Stream<NotifTap> get taps => _taps.stream;
  NotifTap? launchTap;
  bool ready = false, foreground = true, pushReady = false;
  String? _token;

  static const ID_DAILY = 1001, ID_CHALLENGES = 1002, ID_CHEST = 1003, ID_MATCH = 1004, ID_TOUR_BASE = 2000;

  Future<void> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    WidgetsBinding.instance.addObserver(this);
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(_guessZone()));
      } catch (_) {}
      await _p.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) => _emit(r.payload),
      );
      final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final (id, name, desc) in _channels) {
        await android?.createNotificationChannel(AndroidNotificationChannel(id, name, description: desc, importance: id == 'matches' || id == 'messages' ? Importance.high : Importance.defaultImportance));
      }
      final launch = await _p.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) launchTap = _parse(launch!.notificationResponse?.payload);
      ready = true;
    } catch (e) {
      debugPrint('notify init: $e');
    }
  }

  /// asks for POST_NOTIFICATIONS (Android 13+) — called after the intro so the prompt has context
  Future<void> requestPermission() async {
    if (!ready) return;
    try {
      await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => foreground = state == AppLifecycleState.resumed;

  static String _guessZone() {
    final off = DateTime.now().timeZoneOffset.inMinutes;
    return switch (off) { 210 => 'Asia/Tehran', 180 => 'Europe/Istanbul', 240 => 'Asia/Dubai', 60 => 'Europe/Berlin', 0 => 'Europe/London', 120 => 'Europe/Athens', 270 => 'Asia/Kabul', _ => 'UTC' };
  }

  NotifTap? _parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return NotifTap(m['kind'] as String?, Map<String, dynamic>.from((m['data'] as Map?) ?? const {}));
    } catch (_) {
      return NotifTap(payload, const {});
    }
  }

  void _emit(String? payload) {
    final t = _parse(payload);
    if (t != null) _taps.add(t);
  }

  NotificationDetails _details(String channel, {String? tag}) {
    final c = _channels.firstWhere((x) => x.$1 == channel, orElse: () => _channels.first);
    return NotificationDetails(
      android: AndroidNotificationDetails(c.$1, c.$2, channelDescription: c.$3, importance: channel == 'matches' || channel == 'messages' ? Importance.high : Importance.defaultImportance,
          priority: Priority.high, tag: tag, color: const Color(0xFF4FE3FF), styleInformation: const BigTextStyleInformation('')),
      iOS: const DarwinNotificationDetails(),
    );
  }

  static String _channelOf(String? kind) => switch (kind) {
        'dm' => 'messages',
        'follow' || 'friend_request' || 'friend_accept' || 'club_invite' || 'club_request' => 'social',
        'room_invite' || 'match_found' => 'matches',
        'prize' || 'challenge' || 'daily' => 'rewards',
        _ => (kind ?? '').startsWith('tour') || (kind ?? '').startsWith('registration') ? 'tournaments' : 'general',
      };

  Future<void> show(String title, String? body, {String? kind, Map<String, dynamic>? data, int? id}) async {
    if (!ready) return;
    try {
      await _p.show(
        id: id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
        title: title,
        body: body,
        notificationDetails: _details(_channelOf(kind), tag: kind == 'dm' ? 'dm:${data?['conversation']}' : null),
        payload: jsonEncode({'kind': kind, 'data': data ?? const {}}),
      );
    } catch (_) {}
  }

  void showFromRow(Map<String, dynamic> n) => show('${n['title'] ?? 'NEXORA'}', n['body'] as String?, kind: n['kind'] as String?, data: Map<String, dynamic>.from((n['data'] as Map?) ?? const {}));

  Future<void> matchFound(String mode) async {
    if (foreground) return;
    await show('حریف پیدا شد! ⚡', 'مسابقه‌ی $mode آماده است؛ برگرد به بازی', kind: 'match_found', id: ID_MATCH);
  }

  Future<void> _at(int id, DateTime when, String title, String body, String kind, [Map<String, dynamic>? data]) async {
    if (!ready || when.isBefore(DateTime.now().add(const Duration(seconds: 30)))) return;
    try {
      await _p.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details(_channelOf(kind)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: jsonEncode({'kind': kind, 'data': data ?? const {}}),
      );
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (ready) await _p.cancel(id: id).catchError((_) {});
  }

  /// re-plans the reward alarms (called on start and after claiming)
  Future<void> planRewards({required int lastDaily, required int lastChest, required int chestEvery}) async {
    if (!ready) return;
    await cancel(ID_DAILY);
    await cancel(ID_CHEST);
    await cancel(ID_CHALLENGES);
    await _at(ID_DAILY, DateTime.fromMillisecondsSinceEpoch(lastDaily + 86400000), 'جایزه‌ی روزانه آماده است 🎁', 'سر بزن و جایزه‌ی امروزت رو بگیر', 'daily');
    await _at(ID_CHEST, DateTime.fromMillisecondsSinceEpoch(lastChest + chestEvery), 'صندوقچه‌ی رایگان آماده است 📦', 'بازش کن و جایزه بگیر', 'daily');
    // daily challenges refresh at Tehran midnight → remind at 19:00 local if the app was not opened today
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, 19);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    await _at(ID_CHALLENGES, at, 'چالش‌های امروز منتظرتن 🎯', 'تا ۵ الماس جایزه؛ قبل از نیمه‌شب کاملشون کن', 'challenge');
  }

  Future<void> tournamentReminder(String tid, String name, DateTime startsAt) async {
    final id = ID_TOUR_BASE + tid.hashCode.abs() % 5000;
    await _at(id, startsAt.subtract(const Duration(minutes: 10)), 'تورنمنت $name تا ۱۰ دقیقه‌ی دیگر شروع می‌شود 🏆', 'آماده باش و وارد شو', 'tournament', {'tournament': tid});
  }

  // ----------------------------- push (FCM) -----------------------------
  Future<void> initPush() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS) || pushReady) return;
    try {
      if (Firebase.apps.isEmpty) {
        if (_fApiKey.isNotEmpty && _fAppId.isNotEmpty) {
          await Firebase.initializeApp(options: const FirebaseOptions(apiKey: _fApiKey, appId: _fAppId, messagingSenderId: _fSender, projectId: _fProject));
        } else {
          await Firebase.initializeApp(); // needs google-services.json; throws when absent → local-only
        }
      }
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      FirebaseMessaging.onMessage.listen((rm) {
        // foreground: the realtime feed already shows it in-app; only alert when backgrounded
        if (!foreground) show(rm.notification?.title ?? 'NEXORA', rm.notification?.body, kind: rm.data['kind'] as String?, data: Map<String, dynamic>.from(rm.data));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((rm) => _taps.add(NotifTap(rm.data['kind'] as String?, Map<String, dynamic>.from(rm.data))));
      final init = await m.getInitialMessage();
      if (init != null) launchTap = NotifTap(init.data['kind'] as String?, Map<String, dynamic>.from(init.data));
      // ignore: deprecated_member_use
      m.onTokenRefresh.listen(_register);
      // ignore: deprecated_member_use
      final t = await m.getToken();
      if (t != null) await _register(t);
      pushReady = true;
    } catch (e) {
      debugPrint('push disabled: $e');
    }
  }

  Future<void> _register(String t) async {
    _token = t;
    if (supabase.auth.currentUser == null) return;
    await supabase.rpc('register_device', params: {'p_token': t, 'p_platform': Platform.isIOS ? 'ios' : 'android', 'p_locale': Platform.localeName}).catchError((_) => null);
  }

  /// re-bind the token after sign-in / account switch
  Future<void> onSignedIn() async {
    if (_token != null) await _register(_token!);
  }

  Future<void> onSignedOut() async {
    final t = _token;
    if (t != null) await supabase.rpc('unregister_device', params: {'p_token': t}).catchError((_) => null);
  }
}
