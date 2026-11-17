import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/online_service.dart';

/// Admin permissions (server-enforced on both projects; this list only drives the UI).
class AdminPerm {
  const AdminPerm._();
  static const String users = 'users';
  static const String currency = 'currency';
  static const String tournaments = 'tournaments';
  static const String moderation = 'moderation';
  static const String rooms = 'rooms';
  static const String announcements = 'announcements';
  static const String oracle = 'oracle';
  static const String admins = 'admins';
  static const List<String> all = <String>[users, currency, tournaments, moderation, rooms, announcements, oracle, admins];

  static String label(String p, bool fa) => switch (p) {
        users => fa ? 'کاربران و مسدودسازی' : 'Users & bans',
        currency => fa ? 'اهدای سکه و جم' : 'Coin & gem grants',
        tournaments => fa ? 'تورنمنت‌ها' : 'Tournaments',
        moderation => fa ? 'نظارت محتوا' : 'Moderation',
        rooms => fa ? 'اتاق‌ها' : 'Rooms',
        announcements => fa ? 'اطلاعیه‌ها' : 'Announcements',
        oracle => fa ? 'تنظیمات اوراکل' : 'ORACLE config',
        admins => fa ? 'مدیریت ادمین‌ها' : 'Admin management',
        _ => p,
      };
}

/// What the signed-in user may do (`nx_my_access` on the auth project). Refreshed on every auth change.
class AdminAccess extends ChangeNotifier {
  AdminAccess(this._online) {
    _online.addListener(_onAuth);
    _onAuth();
  }

  final OnlineService _online;
  String? _for;
  bool owner = false;
  Set<String> perms = <String>{};
  bool mustChangePassword = false;
  bool organizer = false;
  bool unlimitedGems = false;
  int? gemBudget;
  bool loaded = false;

  bool get isAdmin => owner || perms.isNotEmpty;
  bool can(String p) => owner || perms.contains(p);

  void _onAuth() {
    final String? uid = _online.isOnline ? _online.uid : null;
    if (uid == _for) return;
    _for = uid;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final SupabaseClient? c = _online.client;
    if (c == null || c.auth.currentSession == null) {
      owner = false;
      perms = <String>{};
      mustChangePassword = false;
      loaded = true;
      notifyListeners();
      return;
    }
    try {
      final dynamic r = await c.rpc('nx_my_access');
      if (r is Map) {
        owner = r['owner'] == true;
        perms = ((r['perms'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();
        mustChangePassword = r['must_change_password'] == true;
        organizer = r['organizer'] == true;
        unlimitedGems = r['unlimited'] == true;
        gemBudget = (r['gem_budget'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint('my access: $e');
    }
    loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _online.removeListener(_onAuth);
    super.dispose();
  }
}

final adminAccessProvider = ChangeNotifierProvider<AdminAccess>((ref) => AdminAccess(ref.read(onlineProvider)));

/// Thin wrappers around the admin RPCs. Every call is re-checked and audited on the server.
class AdminApi {
  AdminApi(this._o);
  final OnlineService _o;

  Future<Map<String, dynamic>> _auth(String fn, [Map<String, dynamic>? p]) async {
    try {
      final dynamic r = await _o.rpc(fn, p);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{'ok': r != null, 'value': r};
    } on PostgrestException catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.message};
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> _games(String fn, [Map<String, dynamic>? p]) async {
    try {
      final dynamic r = await _o.grpc(fn, p);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{'ok': r != null, 'value': r};
    } on PostgrestException catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.message};
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> stats() => _auth('nx_owner_stats');
  Future<Map<String, dynamic>> users(String q) =>
      _auth('nx_owner_users', <String, dynamic>{'p_q': q, 'p_limit': 60, 'p_offset': 0});
  Future<Map<String, dynamic>> ban(String user, bool ban, String? reason) =>
      _auth('nx_owner_ban', <String, dynamic>{'p_user': user, 'p_ban': ban, 'p_reason': reason});
  Future<Map<String, dynamic>> grant(String user, int coins, int gems, String? reason) => _auth(
      'nx_owner_grant', <String, dynamic>{'p_user': user, 'p_coins': coins, 'p_gems': gems, 'p_reason': reason});
  Future<Map<String, dynamic>> admins() => _auth('nx_admin_list');
  /// Redeems an owner-issued, single-use tournament-admin invitation code.
  /// The database validates expiry, account status, rate limits and ownership.
  Future<Map<String, dynamic>> redeemAdminCode(String code) =>
      _auth('nx_redeem_admin_code', <String, dynamic>{'p_code': code.trim()});
  Future<Map<String, dynamic>> setPerms(String user, List<String> perms, {bool unlimitedGems = false, int? gemBudget}) =>
      _auth('nx_admin_set_perms', <String, dynamic>{
        'p_user': user,
        'p_perms': perms,
        'p_unlimited_gems': unlimitedGems,
        'p_gem_budget': gemBudget,
      });
  Future<Map<String, dynamic>> setManager(String user, bool manager, {bool unlimited = false, int gemBudget = 0}) =>
      _auth('nx_admin_set_manager', <String, dynamic>{
        'p_user': user,
        'p_manager': manager,
        'p_unlimited': unlimited,
        'p_gem_budget': gemBudget,
      });
  Future<Map<String, dynamic>> audit() => _auth('nx_owner_audit_list');
  Future<Map<String, dynamic>> announcements() => _auth('nx_admin_announcements');
  Future<Map<String, dynamic>> announce(String title, String body, int hours) =>
      _auth('nx_admin_announce', <String, dynamic>{'p_title': title, 'p_body': body, 'p_hours': hours});
  Future<Map<String, dynamic>> endAnnouncement(int id) => _auth('nx_admin_announce_end', <String, dynamic>{'p_id': id});
  Future<Map<String, dynamic>> recentContent() => _auth('nx_admin_recent_content', <String, dynamic>{'p_limit': 60});
  Future<Map<String, dynamic>> remove(String kind, String id, String? reason) =>
      _auth('nx_admin_remove', <String, dynamic>{'p_kind': kind, 'p_id': id, 'p_reason': reason});
  Future<Map<String, dynamic>> rooms() => _games('nx_admin_rooms', <String, dynamic>{'p_limit': 120});
  Future<Map<String, dynamic>> closeRoom(String room, String? reason) =>
      _games('nx_admin_close_room', <String, dynamic>{'p_room': room, 'p_reason': reason});
  Future<Map<String, dynamic>> tournaments() => _games('nx_owner_tournaments', <String, dynamic>{'p_limit': 200});
}

String adminErrorText(String? e, bool fa) => switch (e) {
      'forbidden' => fa ? 'دسترسی نداری' : 'Not allowed',
      'password_change_required' => fa ? 'اول رمزت را عوض کن' : 'Change your password first',
      'cannot_ban_owner' => fa ? 'مدیر اصلی را نمی‌شود مسدود کرد' : 'The main admin cannot be banned',
      'cannot_ban_admin' => fa ? 'فقط مدیر اصلی می‌تواند ادمین را مسدود کند' : 'Only the main admin can ban an admin',
      'cannot_change_owner' => fa ? 'مدیر اصلی قابل تغییر نیست' : 'The main admin cannot be changed',
      'cannot_change_self' => fa ? 'دسترسی خودت را نمی‌توانی عوض کنی' : 'You cannot change your own access',
      'owner_only_admins' => fa ? 'فقط مدیر اصلی «مدیریت ادمین‌ها» را می‌دهد' : 'Only the main admin grants admin management',
      'owner_only_unlimited' => fa ? 'جم نامحدود فقط با مدیر اصلی' : 'Only the main admin grants unlimited gems',
      'account_required' => fa ? 'کاربر باید حساب دائمی داشته باشد (نه مهمان)' : 'The user needs a full account (not a guest)',
      'already_staff' => fa ? 'این حساب از قبل دسترسی مدیریتی دارد' : 'This account already has staff access',
      'bad_code' => fa ? 'کد دعوت معتبر نیست' : 'Invalid admin invitation code',
      'expired' => fa ? 'کد دعوت منقضی شده است' : 'This invitation code has expired',
      'used' => fa ? 'کد دعوت قبلاً استفاده شده است' : 'This invitation code has already been used',
      'insufficient_balance' => fa ? 'موجودی کافی نیست' : 'Insufficient balance',
      'not_found' => fa ? 'پیدا نشد' : 'Not found',
      'tournament_room' => fa ? 'اتاق تورنمنت — از ابزار بازی‌های تورنمنت استفاده کن' : 'Tournament room — use the match tools',
      'network' => fa ? 'اتصال برقرار نیست' : 'No connection',
      null => fa ? 'خطا' : 'Error',
      _ => e,
    };
