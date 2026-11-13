// Supabase client + typed RPC helper with Persian errors — port of src/net/supabase.ts.
// Same project, tables, RPCs and realtime channels as the RN app (supabase/ is unchanged).
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'public_config.dart';

const bool ONLINE_CONFIGURED = PUBLIC_SUPABASE_URL != '' && PUBLIC_SUPABASE_ANON_KEY != '';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: PUBLIC_SUPABASE_URL,
    // ignore: deprecated_member_use
    anonKey: PUBLIC_SUPABASE_ANON_KEY,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true, detectSessionInUri: false),
    realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error, eventsPerSecond: 60),
  );
}

SupabaseClient get supabase => Supabase.instance.client;

final List<(RegExp, String)> _MAP = [
  (RegExp(r'not enough gems', caseSensitive: false), 'الماس کافی نداری'),
  (RegExp(r'already owned', caseSensitive: false), 'این دیسک را قبلاً داری'),
  (RegExp(r'not owned', caseSensitive: false), 'این دیسک را نداری'),
  (RegExp(r'already in club', caseSensitive: false), 'تو الان عضو یک باشگاه هستی'),
  (RegExp(r'club full', caseSensitive: false), 'ظرفیت باشگاه پر است'),
  (RegExp(r'invite only', caseSensitive: false), 'این باشگاه فقط با دعوت عضو می‌گیرد'),
  (RegExp(r'level too low', caseSensitive: false), 'سطحت برای این کار کافی نیست'),
  (RegExp(r'officer only', caseSensitive: false), 'فقط افسران باشگاه'),
  (RegExp(r'leader only', caseSensitive: false), 'فقط رهبر باشگاه'),
  (RegExp(r'admin only', caseSensitive: false), 'فقط مدیران'),
  (RegExp(r'already claimed', caseSensitive: false), 'قبلاً دریافت کردی'),
  (RegExp(r'not completed', caseSensitive: false), 'هنوز کامل نشده'),
  (RegExp(r'bad size', caseSensitive: false), 'اندازه‌ی نامعتبر'),
  (RegExp(r'already joined', caseSensitive: false), 'قبلاً ثبت‌نام کردی'),
  (RegExp(r'\bblocked\b', caseSensitive: false), 'این کاربر تو را مسدود کرده'),
  (RegExp(r'title required', caseSensitive: false), 'عنوان لازم است'),
  (RegExp(r'season running', caseSensitive: false), 'فصل هنوز تمام نشده'),
  (RegExp(r'cannot dm yourself', caseSensitive: false), 'نمی‌توانی به خودت پیام بدهی'),
  (RegExp(r'not public', caseSensitive: false), 'این گفتگو عمومی نیست'),
  (RegExp(r'club not found', caseSensitive: false), 'باشگاه پیدا نشد'),
  (RegExp(r'request not found', caseSensitive: false), 'درخواست پیدا نشد'),
  (RegExp(r'not allowed|bad action', caseSensitive: false), 'اجازه‌ی این کار را نداری'),
  (RegExp(r'clubs_name_key|duplicate key.*clubs.*name', caseSensitive: false), 'این نام باشگاه گرفته شده'),
  (RegExp(r'clubs_tag_key|duplicate key.*tag', caseSensitive: false), 'این تگ گرفته شده'),
  (RegExp(r'tag.*check|clubs_tag_check', caseSensitive: false), 'تگ باید ۲ تا ۵ حرف/عدد انگلیسی بزرگ باشد'),
  (RegExp(r'room not found', caseSensitive: false), 'اتاق پیدا نشد'),
  (RegExp(r'room closed', caseSensitive: false), 'این اتاق بسته شده'),
  (RegExp(r'teams not full', caseSensitive: false), 'هنوز همه‌ی جایگاه‌ها پر نشده'),
  (RegExp(r'not all ready', caseSensitive: false), 'همه‌ی بازیکن‌ها آماده نیستند'),
  (RegExp(r'seat taken', caseSensitive: false), 'این جایگاه گرفته شده'),
  (RegExp(r'host only', caseSensitive: false), 'فقط میزبان می‌تونه این کار رو بکنه'),
  (RegExp(r'organizer only', caseSensitive: false), 'فقط برگزارکننده می‌تونه این کار رو بکنه'),
  (RegExp(r'registration closed', caseSensitive: false), 'ثبت‌نام این تورنمنت بسته شده'),
  (RegExp(r'\bfull\b', caseSensitive: false), 'ظرفیت تکمیل است'),
  (RegExp(r'already started', caseSensitive: false), 'از قبل شروع شده'),
  (RegExp(r'match running', caseSensitive: false), 'بازی در جریان است'),
  (RegExp(r'match not live', caseSensitive: false), 'این مسابقه دیگر فعال نیست'),
  (RegExp(r'match not ready|not playable', caseSensitive: false), 'این مسابقه هنوز آماده نیست'),
  (RegExp(r'not in this match', caseSensitive: false), 'تو در این مسابقه نیستی'),
  (RegExp(r'need at least 2', caseSensitive: false), 'حداقل ۲ شرکت‌کننده لازم است'),
  (RegExp(r'bad slot', caseSensitive: false), 'جایگاه نامعتبر'),
  (RegExp(r'not signed in|JWT|unauthorized', caseSensitive: false), 'اول وارد حساب شو'),
  (RegExp(r'duplicate key.*username|profiles_username_key', caseSensitive: false), 'این نام کاربری قبلاً گرفته شده'),
  (RegExp(r'duplicate key.*tournament_entries|tournament_id, captain', caseSensitive: false), 'قبلاً در این تورنمنت ثبت‌نام کردی'),
  (RegExp(r'username.*check|char_length', caseSensitive: false), 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد'),
  (RegExp(r'Invalid login credentials', caseSensitive: false), 'ایمیل یا رمز عبور اشتباه است'),
  (RegExp(r'Email not confirmed', caseSensitive: false), 'ایمیلت هنوز تأیید نشده؛ صندوق ایمیل را ببین'),
  (RegExp(r'User already registered|already been registered|email_exists', caseSensitive: false), 'با این ایمیل قبلاً حساب ساخته شده'),
  (RegExp(r'Password should be at least|weak_password', caseSensitive: false), 'رمز عبور باید حداقل ۶ کاراکتر باشد'),
  (RegExp(r'rate limit|too many|over_email_send_rate_limit', caseSensitive: false), 'درخواست زیاد بود؛ کمی بعد دوباره امتحان کن'),
  (RegExp(r'invalid.*email|validate email|email_address_invalid', caseSensitive: false), 'ایمیل معتبر نیست'),
  (RegExp(r'Anonymous sign-ins are disabled', caseSensitive: false), 'ورود مهمان غیرفعال است'),
  (RegExp(r'Network request failed|Failed to fetch|fetch failed|timeout|NetworkError', caseSensitive: false), 'اتصال اینترنت برقرار نیست'),
];

String errFa(Object? e) {
  String m;
  if (e is String) {
    m = e;
  } else if (e is PostgrestException) {
    m = e.message;
  } else if (e is AuthException) {
    m = e.message;
  } else {
    m = e?.toString() ?? '';
  }
  for (final (re, fa) in _MAP) {
    if (re.hasMatch(m)) return fa;
  }
  return m.isNotEmpty ? 'خطا: ${m.substring(0, math.min(80, m.length))}' : 'خطای ناشناخته؛ دوباره امتحان کن';
}

/// rpc that throws on error (callers map with errFa)
Future<T> rpc<T>(String fn, [Map<String, dynamic>? args]) async {
  final r = await supabase.rpc(fn, params: args);
  return r as T;
}

int teamSize(String m) => m == '1v1' ? 1 : m == '2v2' ? 2 : 3;
// level formula shared with the backend: level = floor(sqrt(xp/100))+1, xp_for_level(l) = (l-1)^2*100
int xpForLevel(int l) => (math.max(1, l) - 1) * (math.max(1, l) - 1) * 100;
int levelOf(int xp) => math.max(1, (math.sqrt(math.max(0, xp) / 100)).floor() + 1);
({int level, int cur, int need, double frac}) levelProgress(int xp) {
  final l = levelOf(xp), a = xpForLevel(l), b = xpForLevel(l + 1);
  return (level: l, cur: xp - a, need: b - a, frac: (xp - a) / (b - a));
}

/// row helpers (rows stay as JSON maps, same column names as the SQL schema)
typedef JRow = Map<String, dynamic>;
int ri(JRow? r, String k, [int d = 0]) => (r?[k] as num?)?.toInt() ?? d;
String rs(JRow? r, String k, [String d = '']) => r?[k]?.toString() ?? d;
