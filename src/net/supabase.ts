// Supabase client (auth session persisted in AsyncStorage) + typed RPC helper with Persian errors.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';

import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from './publicConfig';

const URL_ = process.env.EXPO_PUBLIC_SUPABASE_URL || PUBLIC_SUPABASE_URL;
const KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || PUBLIC_SUPABASE_ANON_KEY;
export const ONLINE_CONFIGURED = !!(URL_ && KEY);

export const supabase = createClient(URL_ || 'https://invalid.supabase.co', KEY || 'missing', {
  auth: {
    storage: Platform.OS === 'web' && typeof window === 'undefined' ? undefined : AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
  realtime: { params: { log_level: 'error' } },
});

// Refresh tokens only while the app is in the foreground (recommended for RN).
if (Platform.OS !== 'web') {
  AppState.addEventListener('change', s => {
    if (s === 'active') supabase.auth.startAutoRefresh(); else supabase.auth.stopAutoRefresh();
  });
}

// ---------- errors ----------
const MAP: [RegExp, string][] = [
  [/not enough gems/i, 'الماس کافی نداری'],
  [/already owned/i, 'این دیسک را قبلاً داری'],
  [/not owned/i, 'این دیسک را نداری'],
  [/already in club/i, 'تو الان عضو یک باشگاه هستی'],
  [/club full/i, 'ظرفیت باشگاه پر است'],
  [/invite only/i, 'این باشگاه فقط با دعوت عضو می‌گیرد'],
  [/level too low/i, 'سطحت برای این کار کافی نیست'],
  [/officer only/i, 'فقط افسران باشگاه'],
  [/leader only/i, 'فقط رهبر باشگاه'],
  [/admin only/i, 'فقط مدیران'],
  [/already claimed/i, 'قبلاً دریافت کردی'],
  [/not completed/i, 'هنوز کامل نشده'],
  [/bad size/i, 'اندازه‌ی نامعتبر'],
  [/already joined/i, 'قبلاً ثبت‌نام کردی'],
  [/\bblocked\b/i, 'این کاربر تو را مسدود کرده'],
  [/title required/i, 'عنوان لازم است'],
  [/season running/i, 'فصل هنوز تمام نشده'],
  [/cannot dm yourself/i, 'نمی‌توانی به خودت پیام بدهی'],
  [/not public/i, 'این گفتگو عمومی نیست'],
  [/club not found/i, 'باشگاه پیدا نشد'],
  [/request not found/i, 'درخواست پیدا نشد'],
  [/not allowed|bad action/i, 'اجازه‌ی این کار را نداری'],
  [/clubs_name_key|duplicate key.*clubs.*name/i, 'این نام باشگاه گرفته شده'],
  [/clubs_tag_key|duplicate key.*tag/i, 'این تگ گرفته شده'],
  [/tag.*check|clubs_tag_check/i, 'تگ باید ۲ تا ۵ حرف/عدد انگلیسی بزرگ باشد'],
  [/room not found/i, 'اتاق پیدا نشد'],
  [/room closed/i, 'این اتاق بسته شده'],
  [/teams not full/i, 'هنوز همه‌ی جایگاه‌ها پر نشده'],
  [/not all ready/i, 'همه‌ی بازیکن‌ها آماده نیستند'],
  [/seat taken/i, 'این جایگاه گرفته شده'],
  [/host only/i, 'فقط میزبان می‌تونه این کار رو بکنه'],
  [/organizer only/i, 'فقط برگزارکننده می‌تونه این کار رو بکنه'],
  [/registration closed/i, 'ثبت‌نام این تورنمنت بسته شده'],
  [/\bfull\b/i, 'ظرفیت تکمیل است'],
  [/already started/i, 'از قبل شروع شده'],
  [/match running/i, 'بازی در جریان است'],
  [/match not live/i, 'این مسابقه دیگر فعال نیست'],
  [/match not ready|not playable/i, 'این مسابقه هنوز آماده نیست'],
  [/not in this match/i, 'تو در این مسابقه نیستی'],
  [/need at least 2/i, 'حداقل ۲ شرکت‌کننده لازم است'],
  [/bad slot/i, 'جایگاه نامعتبر'],
  [/not signed in|JWT|unauthorized/i, 'اول وارد حساب شو'],
  [/duplicate key.*username|profiles_username_key/i, 'این نام کاربری قبلاً گرفته شده'],
  [/duplicate key.*tournament_entries|tournament_id, captain/i, 'قبلاً در این تورنمنت ثبت‌نام کردی'],
  [/username.*check|char_length/i, 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد'],
  [/Invalid login credentials/i, 'ایمیل یا رمز عبور اشتباه است'],
  [/Email not confirmed/i, 'ایمیلت هنوز تأیید نشده؛ صندوق ایمیل را ببین'],
  [/User already registered|already been registered|email_exists/i, 'با این ایمیل قبلاً حساب ساخته شده'],
  [/Password should be at least|weak_password/i, 'رمز عبور باید حداقل ۶ کاراکتر باشد'],
  [/rate limit|too many|over_email_send_rate_limit/i, 'درخواست زیاد بود؛ کمی بعد دوباره امتحان کن'],
  [/invalid.*email|validate email|email_address_invalid/i, 'ایمیل معتبر نیست'],
  [/Anonymous sign-ins are disabled/i, 'ورود مهمان غیرفعال است'],
  [/Network request failed|Failed to fetch|fetch failed|timeout|NetworkError/i, 'اتصال اینترنت برقرار نیست'],
];
export function errFa(e: unknown): string {
  const m = typeof e === 'string' ? e : (e as any)?.message || (e as any)?.error_description || (e as any)?.msg || '';
  for (const [re, fa] of MAP) if (re.test(m)) return fa;
  return m ? 'خطا: ' + String(m).slice(0, 80) : 'خطای ناشناخته؛ دوباره امتحان کن';
}

// rpc that throws on error (errors are mapped by callers via errFa)
export async function rpc<T = any>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args as any);
  if (error) throw error;
  return data as T;
}

// ---------- shared row types ----------
export type Mode = '1v1' | '2v2' | '3v3';
export type Kind = 'casual' | 'quick' | 'arena' | 'tournament';
export type RoomSettings = { goals: number; time: number; field: number; ball?: number; turn?: number };
export type Room = {
  id: string; code: string; name: string; host: string; mode: Mode; status: 'waiting' | 'playing' | 'finished';
  is_private: boolean; ranked: boolean; voice: boolean; settings: RoomSettings; tournament_match_id: string | null; current_match: string | null; kind: Kind;
  created_at: string; updated_at: string;
};
export type MiniProfile = { username: string; avatar: string; avatar_url: string | null; level: number; rating: number; league: string; equipped_disc: string };
export type RoomPlayer = { room_id: string; user_id: string; role: 'player' | 'spectator'; team: 0 | 1 | null; slot: number | null; ready: boolean; joined_at: string; disc_id: string | null; profiles: MiniProfile | null };
export type RoomListRow = {
  id: string; code: string; name: string; mode: Mode; kind: Kind; host_avatar_url: string | null; status: Room['status']; is_private: boolean; ranked: boolean; voice: boolean; settings: RoomSettings;
  created_at: string; host: string; host_name: string; host_avatar: string; host_level: number; host_league: string; players: number; spectators: number; capacity: number;
};
export type OnlineProfile = {
  id: string; username: string; avatar: string; xp: number; level: number; coins: number; gems: number; rating: number; league: string;
  wins: number; losses: number; draws: number; goals: number; trophies: number; is_guest: boolean; online_at: string; created_at: string;
  avatar_url: string | null; bio: string | null; club_id: string | null; equipped_disc: string; arena_points: number; win_streak: number; best_streak: number;
};
export type Disc = { id: string; cat: string; name: string; price_gems: number; power: number; accuracy: number };
export type League = { id: string; name_fa: string; min_rating: number; color: string; sort: number };
export type Format = 'single_elim' | 'double_elim' | 'round_robin' | 'swiss' | 'league';
export type Tournament = {
  id: string; name: string; format: Format; mode: Mode; max_entries: number; rounds: number | null; status: 'registration' | 'running' | 'finished';
  created_by: string | null; prize_xp: number; prize_coins: number; prize_gems: number; min_level: number; winner_entry: string | null; current_round: number; starts_at: string | null; created_at: string;
};
export type Entry = {
  id: string; tournament_id: string; captain: string; team_name: string; members: string[]; seed: number | null; points: number; played: number;
  wins: number; draws: number; losses: number; gf: number; ga: number; lb_losses: number; eliminated: boolean; final_rank: number | null; pos?: number;
};
export type TMatch = {
  id: string; tournament_id: string; bracket: 'main' | 'winners' | 'losers' | 'final'; round: number; idx: number; entry_a: string | null; entry_b: string | null;
  score_a: number | null; score_b: number | null; winner_entry: string | null; status: 'pending' | 'ready' | 'live' | 'done' | 'bye'; room_id: string | null;
};

export const teamSize = (m: Mode) => (m === '1v1' ? 1 : m === '2v2' ? 2 : 3);
// level formula shared with the backend: level = floor(sqrt(xp/100))+1, xp_for_level(l) = (l-1)^2*100
export const xpForLevel = (l: number) => (Math.max(1, l) - 1) ** 2 * 100;
export const levelOf = (xp: number) => Math.max(1, Math.floor(Math.sqrt(Math.max(0, xp) / 100)) + 1);
export const levelProgress = (xp: number) => {
  const l = levelOf(xp), a = xpForLevel(l), b = xpForLevel(l + 1);
  return { level: l, cur: xp - a, need: b - a, frac: (xp - a) / (b - a) };
};
