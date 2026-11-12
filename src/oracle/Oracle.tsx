// ORACLE — NEXORA's assistant mascot.
//  • OracleProvider: say(text, mood, actions) / react(event) / coach(text) / openPanel() / scene + quiet control
//  • Floating bubble (tabs only, never over critical buttons): draggable, snaps to edges, hover bob, holo glow,
//    blinks, cross-fades between moods, speech bubble with typewriter + action chips, sleeps after 45 s idle
//  • Coach toast (tiny, non-blocking) used in matches and on online screens
//  • Onboarding tour with spotlight ring over each tab
//  • Panel: chat-like Q&A over a local knowledge base + smart actions (quick match, claim rewards, …)
import React, { createContext, memo, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, TextInput, View, useWindowDimensions , Image as RNImage } from 'react-native';
import Animated, { Easing, FadeIn, FadeOut, runOnJS, useAnimatedStyle, useSharedValue, withRepeat, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { GestureDetector, usePanGesture } from 'react-native-gesture-handler';
import { Image } from 'expo-image';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ORACLE } from '../game/assets';
import { Btn, Press, T } from '../ui/kit';
import { Sheet, SheetHandle, TAB_H } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useStore, level as localLevel } from '../store';
import { useAuth } from '../net/auth';
import { useDiscs } from '../net/discs';
import { errFa, levelProgress, rpc, supabase } from '../net/supabase';
import { loadChallenges } from '../online/Challenges';
import type { OnlineEntry } from '../nav';
import { ACTION_LABEL, ActionId, Mood, QUESTION_CHIPS, SUGGESTIONS, matchIntent } from './kb';

export type OracleEvent = 'goal' | 'reward' | 'levelup' | 'purchase' | 'nogems' | 'error' | 'search' | 'challengeDone' | 'message' | 'follow' | 'tourReady';
export type OracleActions = { goTab: (t: 'home' | 'play' | 'social' | 'shop' | 'profile') => void; openOnline: (e?: OnlineEntry, quick?: '1v1' | '2v2' | '3v3') => void; openSettings: () => void; openTeam: () => void };
type Msg = { id: number; text: string; mood: Mood; actions?: ActionId[] };
type Ctx = {
  say: (text: string, mood?: Mood, actions?: ActionId[]) => void;
  react: (ev: OracleEvent, detail?: string) => void;
  coach: (text: string, mood?: Mood) => void;
  openPanel: () => void;
  setScene: (s: 'ui' | 'match') => () => void;
  setQuiet: (key: string, on: boolean) => void;
};
const OracleCtx = createContext<Ctx>({ say: () => {}, react: () => {}, coach: () => {}, openPanel: () => {}, setScene: () => () => {}, setQuiet: () => {} });
export const useOracle = () => useContext(OracleCtx);
export const oracleImg = (m: Mood) => ORACLE[m] || ORACLE.idle;

// lines used by result screens
export const TIPS = [
  'از دیواره‌ها برای ضربه‌ی کمانه‌ای استفاده کن؛ دروازه‌بان‌ها انتظارش رو ندارن.',
  'همیشه قدرت کامل لازم نیست؛ ضربه‌ی متوسط توپ رو کنترل‌شده‌تر می‌بره.',
  'یک دیسک رو جلوی دروازه نگه دار تا ضدحمله‌ها رو خنثی کنه.',
  'قبل از شوت، پیش‌نمایش مسیر رو نگاه کن؛ دیسک‌های دقیق‌تر مسیر بلندتری نشون می‌دن.',
  'با ضربه‌ی اول نمی‌شه گل زد؛ اول توپ رو به موقعیت خوب برسون.',
  'اگر زمان نوبت کمه، یک ضربه‌ی امن دفاعی بهتر از از دست دادن نوبته.',
];
export const tip = () => TIPS[Math.floor(Math.random() * TIPS.length)];
export function resultLine(out: 'victory' | 'defeat' | 'draw'): { mood: Mood; text: string } {
  if (out === 'victory') return { mood: Math.random() < .5 ? 'joy' : 'laugh', text: ['عالی بود کاپیتان! 🏆', 'چه بردی! کهکشان به احترامت ایستاده. ✨', 'همین‌طوری ادامه بده، قهرمان! 🔥'][Math.floor(Math.random() * 3)] };
  if (out === 'defeat') return { mood: 'calm', text: `اشکالی نداره، دست بعدی مال ماست. 💙 نکته: ${tip()}` };
  return { mood: 'content', text: 'مساوی! فقط یک ضربه تا برد فاصله داشتیم. 🤝' };
}

export function OracleProvider({ children, actions, tabsVisible }: { children: React.ReactNode; actions: OracleActions; tabsVisible: boolean }) {
  const { p, set } = useStore();
  const auth = useAuth(); const dz = useDiscs();
  const enabled = p.oracle !== false;
  const [scene, setSceneState] = useState<'ui' | 'match'>('ui');
  const [msg, setMsg] = useState<Msg | null>(null);
  const [mood, setMood] = useState<Mood>('idle');
  const [coachMsg, setCoachMsg] = useState<{ id: number; text: string; mood: Mood } | null>(null);
  const [panel, setPanel] = useState(false);
  const [tour, setTour] = useState<number | null>(null);
  const [sleeping, setSleeping] = useState(false);
  const quiet = useRef(new Set<string>());
  const lastReact = useRef<Record<string, number>>({});
  const idleT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const hideT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const coachT = useRef<ReturnType<typeof setTimeout> | null>(null);
  const actRef = useRef(actions); actRef.current = actions;
  const showBubble = enabled && tabsVisible && scene === 'ui';
  const showRef = useRef(showBubble); showRef.current = showBubble;

  const say = useCallback((text: string, m: Mood = 'content', acts?: ActionId[]) => {
    setSleeping(false); setMood(m); setMsg({ id: Date.now(), text, mood: m, actions: acts });
    if (hideT.current) clearTimeout(hideT.current);
    hideT.current = setTimeout(() => { setMsg(null); setMood('idle'); }, Math.min(14000, 4500 + text.length * 55));
  }, []);
  const coach = useCallback((text: string, m: Mood = 'idea') => {
    if (!enabledRef.current) return;
    setCoachMsg({ id: Date.now(), text, mood: m });
    if (coachT.current) clearTimeout(coachT.current);
    coachT.current = setTimeout(() => setCoachMsg(null), 3600);
  }, []);
  const enabledRef = useRef(enabled); enabledRef.current = enabled;

  // speak in the bubble when it is visible, otherwise as a small toast
  const announce = useCallback((text: string, m: Mood, acts?: ActionId[]) => { if (showRef.current) say(text, m, acts); else coach(text, m); }, [say, coach]);

  const react = useCallback((ev: OracleEvent, detail?: string) => {
    if (!enabledRef.current) return;
    const now = Date.now(), gap: Record<OracleEvent, number> = { goal: 3000, reward: 2500, levelup: 1000, purchase: 2000, nogems: 15000, error: 20000, search: 5000, challengeDone: 4000, message: 8000, follow: 5000, tourReady: 10000 };
    if (now - (lastReact.current[ev] || 0) < gap[ev]) return; lastReact.current[ev] = now;
    if (ev === 'message' && quiet.current.has('chat')) return;
    switch (ev) {
      case 'goal': coach(['گووووول! 🔥', 'چه ضربه‌ای! 😄', 'تور دروازه لرزید! ⚡'][Math.floor(Math.random() * 3)], Math.random() < .5 ? 'excited' : 'laugh'); break;
      case 'reward': announce(detail ? `جایزه رسید: ${detail} 🎁` : 'جایزه‌ات رسید! 🎁', 'joy'); break;
      case 'levelup': announce(detail ? `سطح ${detail}! داری قوی‌تر می‌شی کاپیتان 🚀` : 'سطح جدید! 🚀', 'spin'); break;
      case 'purchase': announce('مبارکت باشه! با این یکی حسابی می‌درخشی ✨', 'happy'); break;
      case 'nogems': announce('الماس کافی نداری 🤔 چالش‌های روزانه (تا ۵)، جایزه‌ی فصل (تا ۳۰) و قهرمانی تورنمنت (تا ۳۰) الماس می‌دن.', 'confused', ['challenges', 'tours']); break;
      case 'error': announce(`اوه! ${detail || 'یه مشکلی پیش اومد'} — نگران نباش، دوباره امتحان می‌کنیم.`, 'alert'); break;
      case 'search': coach('دارم حریف پیدا می‌کنم… 🔭', 'spin'); break;
      case 'challengeDone': announce(`چالش «${detail || ''}» کامل شد! جایزه‌ات رو بگیر 🎉`, 'excited', ['claim']); break;
      case 'message': announce(detail ? `پیام جدید از ${detail} 💬` : 'پیام جدید داری 💬', 'curious', ['messages']); break;
      case 'follow': announce(detail ? `${detail} دنبالت کرد! 👀` : 'یک دنبال‌کننده‌ی جدید داری 👀', 'curious'); break;
      case 'tourReady': announce('مسابقه‌ی تورنمنتت آماده‌ست! ⚠️ زود وارد شو.', 'alert', ['tours']); break;
    }
  }, [announce, coach]);

  const setScene = useCallback((s: 'ui' | 'match') => { setSceneState(s); return () => setSceneState('ui'); }, []);
  const setQuiet = useCallback((k: string, on: boolean) => { if (on) quiet.current.add(k); else quiet.current.delete(k); }, []);

  // idle → sleep after 45 s without touches
  const poke = useCallback(() => {
    if (idleT.current) clearTimeout(idleT.current);
    if (sleepingRef.current) { setSleeping(false); setMood('idle'); }
    idleT.current = setTimeout(() => { if (showRef.current) { setSleeping(true); setMsg(null); setMood('sleep'); } }, 45000);
  }, []);
  const sleepingRef = useRef(sleeping); sleepingRef.current = sleeping;
  useEffect(() => { poke(); return () => { [idleT, hideT, coachT].forEach(r => r.current && clearTimeout(r.current)); }; }, []);

  // greeting + first-run tour
  const greeted = useRef(false);
  useEffect(() => {
    if (!enabled || !tabsVisible || greeted.current) return;
    greeted.current = true;
    const t = setTimeout(() => {
      if (!p.oracleTour) { setTour(0); return; }
      const h = new Date().getHours();
      const g = h >= 5 && h < 12 ? 'صبح بخیر' : h < 17 ? 'روز بخیر' : h < 21 ? 'عصر بخیر' : 'شب بخیر';
      const name = auth.profile?.username || p.name;
      say(`${g} ${name}! 👋 آماده‌ی یک مسابقه‌ی کهکشانی هستی؟`, h >= 5 && h < 12 ? 'hello' : 'wave', ['quick', 'challenges']);
    }, 2600);
    return () => clearTimeout(t);
  }, [enabled, tabsVisible]);

  // live social / challenge events
  const uid = auth.uid;
  useEffect(() => {
    if (!uid) return;
    let completed = new Set<string>(); let primed = false;
    const check = async () => {
      try {
        const list = await loadChallenges();
        const now = new Set(list.filter(c => c.progress >= c.target && !c.claimed).map(c => c.def_id));
        if (primed) for (const c of list) if (now.has(c.def_id) && !completed.has(c.def_id)) react('challengeDone', c.title_fa);
        completed = now; primed = true;
      } catch { }
    };
    check();
    const ch = supabase.channel(`oracle:${uid}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'user_challenges', filter: `user_id=eq.${uid}` }, () => check())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'follows', filter: `followee=eq.${uid}` }, async pl => {
        const { data } = await supabase.from('profiles').select('username').eq('id', (pl.new as any).follower).maybeSingle();
        react('follow', data?.username);
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, async pl => {
        const m = pl.new as any; if (!m || m.sender === uid) return;
        const { data } = await supabase.from('profiles').select('username').eq('id', m.sender).maybeSingle();
        react('message', data?.username);
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [uid]);

  // ---------- smart actions ----------
  const runAction = useCallback(async (id: ActionId): Promise<{ text: string; mood: Mood; actions?: ActionId[] } | null> => {
    const a = actRef.current;
    const needOnline = async () => { if (auth.uid) return true; try { return !!(await auth.ensure()); } catch { return false; } };
    switch (id) {
      case 'quick': setPanel(false); a.openOnline('hub', '1v1'); return { text: 'دارم یک حریف هم‌سطح برات پیدا می‌کنم… 🔭', mood: 'spin' };
      case 'shop': setPanel(false); a.goTab('shop'); return { text: 'فروشگاه باز شد! 🛍', mood: 'happy' };
      case 'tours': setPanel(false); a.openOnline('tours'); return { text: 'بریم سراغ تورنمنت‌ها! 🏆', mood: 'excited' };
      case 'clubs': case 'messages': setPanel(false); a.goTab('social'); return { text: id === 'clubs' ? 'باشگاه‌ها در تب «اجتماعی» هستن 🛡' : 'پیام‌هات این‌جاست 💬', mood: 'curious' };
      case 'online': setPanel(false); a.openOnline('hub'); return { text: 'به بخش آنلاین خوش اومدی! 🌐', mood: 'wave' };
      case 'arena': setPanel(false); a.openOnline('arena'); return { text: 'آرنا منتظرته! ⚔️', mood: 'excited' };
      case 'leagues': setPanel(false); a.openOnline('leagues'); return { text: 'لیگ‌ها و جایزه‌های فصل 🥇', mood: 'present' };
      case 'team': setPanel(false); a.openTeam(); return { text: 'تیم و دیسک‌هات این‌جاست ⚽', mood: 'present' };
      case 'settings': setPanel(false); a.openSettings(); return { text: 'تنظیمات باز شد ⚙️', mood: 'neutral' };
      case 'challenges': {
        if (!(await needOnline())) return { text: 'برای چالش‌ها باید آنلاین باشی 📶', mood: 'alert' };
        try {
          const list = await loadChallenges();
          const lines = list.map(c => `${c.claimed ? '✅' : c.progress >= c.target ? '🎁' : '▫️'} ${c.title_fa} — ${fa(Math.min(c.progress, c.target))}/${fa(c.target)} (💎${fa(c.reward_gems)})`);
          return { text: `چالش‌های امروز:\n${lines.join('\n')}`, mood: 'present', actions: list.some(c => c.progress >= c.target && !c.claimed) ? ['claim'] : undefined };
        } catch (e) { return { text: errFa(e), mood: 'alert' }; }
      }
      case 'claim': {
        if (!(await needOnline())) return { text: 'برای گرفتن جایزه باید آنلاین باشی 📶', mood: 'alert' };
        let gems = 0, xp = 0, n = 0;
        try {
          const list = await loadChallenges();
          for (const c of list) if (c.progress >= c.target && !c.claimed) { try { const r = await rpc<{ gems: number; xp: number }>('claim_challenge', { p_def: c.def_id }); gems += r.gems; xp += r.xp; n++; } catch { } }
        } catch { }
        let season = 0; try { const r = await rpc<{ gems: number }>('claim_season_reward'); season = r.gems; gems += r.gems; } catch { }
        if (!n && !season) return { text: 'فعلاً جایزه‌ی آماده‌ای نداری. چالش‌های امروز رو کامل کن تا الماس بگیری! 💪', mood: 'calm', actions: ['challenges'] };
        sfx('win'); buzz('success'); auth.refreshProfile();
        return { text: `گرفتمشون! 🎉 ${n ? `${fa(n)} چالش` : ''}${n && season ? ' و ' : ''}${season ? 'جایزه‌ی فصل' : ''}: +${fa(gems)} الماس${xp ? ` · +${fa(xp)} XP` : ''}`, mood: 'joy' };
      }
      case 'disc': {
        const cat = Object.values(dz.catalog);
        if (!cat.length) return { text: 'کاتالوگ دیسک‌ها هنوز بارگذاری نشده؛ یک لحظه بعد دوباره بپرس.', mood: 'confused' };
        const gems = auth.profile?.gems ?? 0, score = (d: { power: number; accuracy: number }) => d.power + d.accuracy;
        const afford = cat.filter(d => !dz.has(d.id) && d.price_gems > 0 && d.price_gems <= gems).sort((a, b) => score(b) - score(a) || a.price_gems - b.price_gems)[0];
        const owned = cat.filter(d => dz.has(d.id)).sort((a, b) => score(b) - score(a))[0];
        const next = cat.filter(d => !dz.has(d.id) && d.price_gems > gems).sort((a, b) => a.price_gems - b.price_gems || score(b) - score(a))[0];
        const lines: string[] = [];
        if (afford) lines.push(`با ${fa(gems)} الماست بهترین انتخاب «${afford.name}» است: قدرت ${fa(afford.power)}، دقت ${fa(afford.accuracy)} به قیمت 💎${fa(afford.price_gems)}.`);
        if (owned) lines.push(`بهترین دیسکی که الان داری «${owned.name}» است (قدرت ${fa(owned.power)}، دقت ${fa(owned.accuracy)})${p.team !== owned.id ? ' — مجهزش کن!' : ' و فعاله ✅'}`);
        if (!afford && next) lines.push(`هدف بعدی: «${next.name}» با 💎${fa(next.price_gems)}؛ ${fa(next.price_gems - gems)} الماس دیگه لازم داری.`);
        return { text: lines.join('\n') || 'همه‌ی دیسک‌ها رو داری، اسطوره! 🤯', mood: 'idea', actions: ['team', 'shop'] };
      }
      case 'stats': {
        const pr = auth.profile;
        if (pr) {
          const pl = pr.wins + pr.losses + pr.draws, wr = pl ? Math.round(pr.wins / pl * 100) : 0, lp = levelProgress(pr.xp);
          const { data: lg } = await supabase.from('leagues').select('*').order('min_rating');
          const nx = (lg || []).find((l: any) => l.min_rating > pr.rating) as any;
          return { text: `📊 ${pr.username}\n• سطح ${fa(lp.level)} — ${fa(lp.need - lp.cur)} XP تا سطح بعد\n• ${fa(pl)} بازی آنلاین، درصد برد ${fa(wr)}٪\n• برد پیاپی ${fa(pr.win_streak)} (رکورد ${fa(pr.best_streak)})\n• امتیاز ${fa(pr.rating)}${nx ? ` — ${fa(nx.min_rating - pr.rating)} تا لیگ ${nx.name_fa}` : ' — بالاترین لیگ!'}\n• آرنا ${fa(pr.arena_points)} · 💎 ${fa(pr.gems)}`, mood: 'present', actions: ['leagues'] };
        }
        const lv = localLevel(p.xp), wr = p.played ? Math.round(p.wins / p.played * 100) : 0;
        return { text: `📊 آمار آفلاین\n• سطح ${fa(lv.level)}\n• ${fa(p.played)} بازی، درصد برد ${fa(wr)}٪\n• بهترین برد پیاپی ${fa(p.bestStreak)}\nبرای آمار آنلاین وارد بخش آنلاین شو.`, mood: 'present', actions: ['online'] };
      }
    }
    return null;
  }, [auth.uid, auth.profile, dz.catalog, dz.has, p.team, p.xp]);

  const v = useMemo<Ctx>(() => ({ say, react, coach, openPanel: () => setPanel(true), setScene, setQuiet }), [say, react, coach, setScene, setQuiet]);
  const endTour = () => { setTour(null); set({ oracleTour: true }); say('هر وقت سؤالی داشتی روی من بزن! 💙', 'wave', ['quick']); };

  const panelRef = useRef(panel); panelRef.current = panel;
  return (
    <OracleCtx.Provider value={v}>
      <View style={{ flex: 1 }} onTouchStart={poke}>
        {children}
        {showBubble && tour === null ? (
          <Bubble mood={mood} msg={msg} sleeping={sleeping} onTap={() => { if (sleeping) { setSleeping(false); say('بیدارم! 😄 چه کمکی از دستم برمیاد؟', 'wave', SUGGESTIONS.slice(0, 3)); } else setPanel(true); }}
            onAction={async a => { setMsg(null); const r = await runAction(a); if (r && !panelRef.current) say(r.text, r.mood, r.actions); }} onClose={() => { setMsg(null); setMood('idle'); }} />
        ) : null}
        {coachMsg && enabled ? <Coach key={coachMsg.id} text={coachMsg.text} mood={coachMsg.mood} match={scene === 'match'} /> : null}
        {tour !== null && enabled && tabsVisible ? <Tour step={tour} goTab={actions.goTab} onNext={() => (tour >= TOUR.length - 1 ? endTour() : setTour(tour + 1))} onSkip={endTour} /> : null}
        {panel ? <OraclePanel onClose={() => setPanel(false)} runAction={runAction} /> : null}
      </View>
    </OracleCtx.Provider>
  );
}

// ============================ floating bubble ============================
const SPR = 72;
const OracleSprite = memo(function OracleSprite({ mood, size = SPR, blink = true }: { mood: Mood; size?: number; blink?: boolean }) {
  // two stacked layers → cross-fade on mood change; occasional "blink" by swapping to the calm sprite
  const [a, setA] = useState<Mood>(mood); const [b, setB] = useState<Mood>(mood);
  const [front, setFront] = useState<0 | 1>(0);
  const mix = useSharedValue(0); // 0 → layer a visible, 1 → layer b visible
  useEffect(() => {
    if ((front === 0 ? a : b) === mood) return;
    if (front === 0) { setB(mood); setFront(1); mix.value = withTiming(1, { duration: 260 }); }
    else { setA(mood); setFront(0); mix.value = withTiming(0, { duration: 260 }); }
  }, [mood]);
  const [blinking, setBlinking] = useState(false);
  useEffect(() => {
    if (!blink) return;
    let t: ReturnType<typeof setTimeout>;
    const loop = () => { t = setTimeout(() => { setBlinking(true); setTimeout(() => setBlinking(false), 170); loop(); }, 3500 + Math.random() * 3500); };
    loop(); return () => clearTimeout(t);
  }, [blink]);
  const sa = useAnimatedStyle(() => ({ opacity: 1 - mix.value }));
  const sb = useAnimatedStyle(() => ({ opacity: mix.value }));
  const cur = front === 0 ? a : b;
  const showBlink = blinking && (cur === 'idle' || cur === 'neutral');
  return (
    <View style={{ width: size, height: size }}>
      <Animated.View style={[StyleSheet.absoluteFill, sa]}><Image source={oracleImg(showBlink && front === 0 ? 'content' : a)} style={{ width: size, height: size }} contentFit="contain" cachePolicy="memory-disk" transition={0} /></Animated.View>
      <Animated.View style={[StyleSheet.absoluteFill, sb]}><Image source={oracleImg(showBlink && front === 1 ? 'content' : b)} style={{ width: size, height: size }} contentFit="contain" cachePolicy="memory-disk" transition={0} /></Animated.View>
    </View>
  );
});

function Bubble({ mood, msg, sleeping, onTap, onAction, onClose }: { mood: Mood; msg: Msg | null; sleeping: boolean; onTap: () => void; onAction: (a: ActionId) => void; onClose: () => void }) {
  const { width: W, height: H } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const minY = ins.top + 120, maxY = H - (TAB_H + Math.max(10, ins.bottom) + 10) - SPR;
  const x = useSharedValue(12), y = useSharedValue(maxY), sx = useSharedValue(0), sy = useSharedValue(0);
  const bob = useSharedValue(0), glow = useSharedValue(0);
  const [side, setSide] = useState<'left' | 'right'>('left');
  useEffect(() => {
    bob.value = withRepeat(withTiming(1, { duration: 2200, easing: Easing.inOut(Easing.sin) }), -1, true);
    glow.value = withRepeat(withTiming(1, { duration: 1600, easing: Easing.inOut(Easing.quad) }), -1, true);
  }, []);
  useEffect(() => { y.value = Math.min(Math.max(y.value, minY), maxY); }, [maxY]);
  const pan = usePanGesture({
    minDistance: 8,
    onActivate: () => { 'worklet'; sx.value = x.value; sy.value = y.value; },
    onUpdate: (e: any) => { 'worklet'; x.value = sx.value + e.translationX; y.value = Math.min(maxY, Math.max(minY, sy.value + e.translationY)); },
    onDeactivate: () => {
      'worklet';
      const right = x.value + SPR / 2 > W / 2;
      x.value = withSpring(right ? W - SPR - 12 : 12, { damping: 16, stiffness: 180 });
      runOnJS(setSide)(right ? 'right' : 'left');
    },
  });
  const pos = useAnimatedStyle(() => ({ transform: [{ translateX: x.value }, { translateY: y.value + (bob.value - .5) * 8 }] }));
  const pad = useAnimatedStyle(() => ({ opacity: .35 + glow.value * .45, transform: [{ scaleX: 1 + glow.value * .12 }] }));
  const bubbleW = Math.min(W - SPR - 40, 280);
  return (
    <View pointerEvents="box-none" style={[StyleSheet.absoluteFill, { zIndex: 45 }]}>
      <GestureDetector gesture={pan}>
        <Animated.View style={[{ position: 'absolute', left: 0, top: 0, width: SPR, height: SPR + 10 }, pos]}>
          <Animated.View style={[st.pad, pad]} />
          <Pressable onPress={onTap} hitSlop={6} accessibilityRole="button" accessibilityLabel="اوراکل">
            <OracleSprite mood={sleeping ? 'sleep' : mood} />
          </Pressable>
          {msg ? (
            <Animated.View entering={FadeIn.duration(180)} exiting={FadeOut.duration(150)} style={[st.speech, { width: bubbleW, bottom: SPR - 6 }, side === 'left' ? { left: SPR - 14 } : { right: SPR - 14 }]}>
              <Typewriter key={msg.id} text={msg.text} />
              {msg.actions?.length ? (
                <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', marginTop: 6, gap: 6 }}>
                  {msg.actions.map(a => <Chip key={a} label={ACTION_LABEL[a]} onPress={() => onAction(a)} />)}
                </View>
              ) : null}
              <Pressable onPress={onClose} hitSlop={10} style={st.x}><T s="✕" style={{ fontSize: 11, color: C.dim }} /></Pressable>
            </Animated.View>
          ) : null}
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const Typewriter = memo(function Typewriter({ text, speed = 18 }: { text: string; speed?: number }) {
  const [n, setN] = useState(0);
  useEffect(() => {
    setN(0); let i = 0;
    const id = setInterval(() => { i = Math.min(text.length, i + 2); setN(i); if (i >= text.length) clearInterval(id); }, speed);
    return () => clearInterval(id);
  }, [text]);
  return <T s={text.slice(0, n) || ' '} style={{ fontSize: 13, lineHeight: 21, textAlign: 'right' }} />;
});

const Chip = ({ label, onPress }: { label: string; onPress: () => void }) => (
  <Press onPress={onPress} style={st.chip} scaleTo={.95}><T s={label} n={1} style={{ fontFamily: F.bold, fontSize: 11, color: C.cyan }} /></Press>
);

function Coach({ text, mood, match }: { text: string; mood: Mood; match: boolean }) {
  const ins = useSafeAreaInsets();
  return (
    <Animated.View pointerEvents="none" entering={FadeIn.duration(200)} exiting={FadeOut.duration(200)}
      style={[st.coach, match ? { top: ins.top + 108 } : { bottom: Math.max(ins.bottom, 12) + 12 }]}>
      <OracleSprite mood={mood} size={38} blink={false} />
      <T s={text} n={3} style={{ fontSize: 12, lineHeight: 19, flexShrink: 1, textAlign: 'right', marginRight: 6 }} />
    </Animated.View>
  );
}

// ============================ onboarding tour ============================
const TOUR: { tab: 'home' | 'play' | 'social' | 'shop' | 'profile' | null; idx: number; text: string; mood: Mood }[] = [
  { tab: null, idx: -1, text: 'سلام! من اوراکل‌ام 🤖 بذار در چند ثانیه ایستگاه NEXORA رو نشونت بدم.', mood: 'hello' },
  { tab: 'home', idx: 0, text: 'خانه: جایزه‌ی روزانه، چالش‌های امروز و ورود سریع به بخش آنلاین این‌جاست.', mood: 'present' },
  { tab: 'play', idx: 1, text: 'بازی: مقابل ربات یا دو نفره روی یک گوشی، و آنلاین: مسابقه‌ی سریع، آرنا، اتاق‌ها، تورنمنت و لیگ.', mood: 'excited' },
  { tab: 'social', idx: 2, text: 'اجتماعی: پیام بده، گروه و کانال بساز، دوست دنبال کن و به یک باشگاه بپیوند.', mood: 'curious' },
  { tab: 'shop', idx: 3, text: 'فروشگاه: دیسک‌ها با الماس، توپ و زمین با سکه. قدرت و دقت هر دیسک در بازی واقعاً اثر داره!', mood: 'happy' },
  { tab: 'profile', idx: 4, text: 'پروفایل: عکس، سطح، لیگ و آمار. حساب مهمانت رو هم از تنظیمات به ایمیل وصل کن.', mood: 'idea' },
  { tab: 'home', idx: -1, text: 'هر وقت سؤال داشتی روی من بزن؛ من این گوشه منتظرم. بزن بریم! 🚀', mood: 'joy' },
];
function Tour({ step, goTab, onNext, onSkip }: { step: number; goTab: OracleActions['goTab']; onNext: () => void; onSkip: () => void }) {
  const { width: W, height: H } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const s = TOUR[step];
  useEffect(() => { if (s.tab) goTab(s.tab); sfx('ui'); }, [step]);
  const ring = useSharedValue(0);
  useEffect(() => { ring.value = withRepeat(withSequence(withTiming(1, { duration: 700 }), withTiming(0, { duration: 700 })), -1, false); }, []);
  const rs = useAnimatedStyle(() => ({ transform: [{ scale: 1 + ring.value * .12 }], opacity: .6 + ring.value * .4 }));
  const barW = Math.min(W - 20, 520), cw = barW / 5;
  const cx = (W + barW) / 2 - cw * (s.idx + .5), cy = H - Math.max(10, ins.bottom) - (TAB_H - 8) / 2;
  return (
    <View style={[StyleSheet.absoluteFill, { zIndex: 85 }]}>
      <View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(1,3,12,.72)' }]} />
      {s.idx >= 0 ? <Animated.View pointerEvents="none" style={[st.spot, { left: cx - 40, top: cy - 40 }, rs]} /> : null}
      <Animated.View key={step} entering={FadeIn.duration(250)} style={[st.tourCard, { bottom: TAB_H + Math.max(10, ins.bottom) + 40 }]}>
        <View style={{ flexDirection: 'row-reverse', alignItems: 'flex-end' }}>
          <OracleSprite mood={s.mood} size={92} blink={false} />
          <View style={st.tourText}><Typewriter text={s.text} /></View>
        </View>
        <View style={{ flexDirection: 'row-reverse', marginTop: 12 }}>
          <Btn label={step >= TOUR.length - 1 ? 'شروع' : 'بعدی'} small onPress={onNext} style={{ flex: 1, marginLeft: 8 }} />
          {step < TOUR.length - 1 ? <Btn label="رد کردن" small colors={G.dark} onPress={onSkip} style={{ width: 110 }} /> : null}
        </View>
        <View style={{ flexDirection: 'row', justifyContent: 'center', marginTop: 10 }}>
          {TOUR.map((_, i) => <View key={i} style={{ width: i === step ? 16 : 6, height: 6, borderRadius: 3, marginHorizontal: 3, backgroundColor: i === step ? C.cyan : 'rgba(255,255,255,.25)' }} />)}
        </View>
      </Animated.View>
    </View>
  );
}

// ============================ panel (Q&A) ============================
type PMsg = { id: number; from: 'me' | 'oracle'; text: string; mood?: Mood; actions?: ActionId[] };
function OraclePanel({ onClose, runAction }: { onClose: () => void; runAction: (a: ActionId) => Promise<{ text: string; mood: Mood; actions?: ActionId[] } | null> }) {
  const ins = useSafeAreaInsets();
  const sheet = useRef<SheetHandle>(null);
  const [msgs, setMsgs] = useState<PMsg[]>([{ id: 1, from: 'oracle', text: 'سلام کاپیتان! 👋 هر سؤالی درباره‌ی بازی داری بپرس یا یکی از کارهای سریع رو انتخاب کن.', mood: 'wave', actions: SUGGESTIONS }]);
  const [txt, setTxt] = useState(''); const [busy, setBusy] = useState(false);
  const mood = msgs.filter(m => m.from === 'oracle').slice(-1)[0]?.mood || 'idle';
  const push = (m: Omit<PMsg, 'id'>) => setMsgs(s => [...s, { ...m, id: Date.now() + Math.random() }]);
  const doAction = async (a: ActionId) => {
    if (busy) return; setBusy(true); push({ from: 'me', text: ACTION_LABEL[a] });
    try { const r = await runAction(a); if (r) push({ from: 'oracle', ...r }); } finally { setBusy(false); }
  };
  const ask = async (q: string) => {
    const t = q.trim(); if (!t || busy) return; setTxt('');
    push({ from: 'me', text: t });
    const { intent, action } = matchIntent(t);
    if (action) { setBusy(true); try { const r = await runAction(action); if (r) push({ from: 'oracle', ...r }); } finally { setBusy(false); } return; }
    if (intent) { push({ from: 'oracle', text: intent.answer, mood: intent.mood, actions: intent.actions }); sfx('chat'); return; }
    push({ from: 'oracle', text: 'هممم… این رو متوجه نشدم 🤔 می‌تونی دربار‌ه‌ی شوت، الماس، دیسک‌ها، تورنمنت، آرنا، باشگاه یا حساب بپرسی، یا یکی از این‌ها رو بزنی:', mood: 'confused', actions: SUGGESTIONS });
  };
  return (
    <Sheet ref={sheet} onClosed={onClose} title="اوراکل" en="ORACLE · ASSISTANT" accent={C.cyan} height={.94}>
      <View style={{ flex: 1 }}>
        <View style={{ height: 120, alignItems: 'center', justifyContent: 'center' }}>
          <View style={st.heroGlow} />
          <OracleSprite mood={mood === 'idle' ? 'idle' : mood} size={110} />
        </View>
        <FlatList data={msgs.slice().reverse()} inverted keyExtractor={m => String(m.id)} style={{ flex: 1 }} contentContainerStyle={{ padding: 12 }}
          renderItem={({ item }) => (
            <View style={{ alignItems: item.from === 'me' ? 'flex-start' : 'flex-end', marginVertical: 4 }}>
              <View style={[st.pm, item.from === 'me' ? st.pmMe : st.pmO]}>
                <T s={item.text} style={{ fontSize: 13, lineHeight: 21, textAlign: 'right' }} />
                {item.actions?.length ? (
                  <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', marginTop: 8, gap: 6 }}>
                    {item.actions.map(a => <Chip key={a} label={ACTION_LABEL[a]} onPress={() => doAction(a)} />)}
                  </View>
                ) : null}
              </View>
            </View>
          )} keyboardShouldPersistTaps="handled" />
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12, gap: 6, flexDirection: 'row-reverse' }} style={{ flexGrow: 0, marginBottom: 6 }}>
          {QUESTION_CHIPS.map(q => <Chip key={q} label={q} onPress={() => ask(q)} />)}
        </ScrollView>
        <View style={[st.inRow, { paddingBottom: Math.max(ins.bottom, 8) }]}>
          <Press onPress={() => ask(txt)} disabled={!txt.trim() || busy} style={st.send}><T s={busy ? '…' : '➤'} style={{ fontSize: 18, color: C.cyan, transform: [{ scaleX: -1 }] }} /></Press>
          <TextInput value={txt} onChangeText={setTxt} onSubmitEditing={() => ask(txt)} returnKeyType="send" placeholder="از اوراکل بپرس…" placeholderTextColor={C.dim2}
            style={st.in} selectionColor={C.cyan} allowFontScaling={false} maxLength={200} />
        </View>
      </View>
    </Sheet>
  );
}

// preload every sprite into the image cache
export function prefetchOracle() {
  try { const uris = Object.values(ORACLE).map((m: any) => RNImage.resolveAssetSource?.(m)?.uri).filter(Boolean) as string[]; if (uris.length) Image.prefetch(uris, 'memory-disk').catch(() => {}); } catch { }
}

const st = StyleSheet.create({
  pad: { position: 'absolute', bottom: 0, left: 8, width: SPR - 16, height: 12, borderRadius: 8, backgroundColor: C.cyan, shadowColor: C.cyan, shadowOpacity: 1, shadowRadius: 10 },
  speech: { position: 'absolute', padding: 12, paddingTop: 14, borderRadius: 18, backgroundColor: 'rgba(10,18,52,.97)', borderWidth: 1, borderColor: 'rgba(92,225,255,.55)', shadowColor: C.cyan, shadowOpacity: .4, shadowRadius: 12, elevation: 12 },
  x: { position: 'absolute', top: 4, left: 6, width: 22, height: 22, alignItems: 'center', justifyContent: 'center' },
  chip: { height: 34, paddingHorizontal: 12, borderRadius: 17, borderWidth: 1, borderColor: C.cyan + '88', backgroundColor: 'rgba(79,227,255,.1)', justifyContent: 'center' },
  coach: { position: 'absolute', alignSelf: 'center', left: 24, right: 24, flexDirection: 'row-reverse', alignItems: 'center', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 20, backgroundColor: 'rgba(8,14,40,.92)', borderWidth: 1, borderColor: 'rgba(92,225,255,.45)', zIndex: 95 },
  spot: { position: 'absolute', width: 80, height: 80, borderRadius: 40, borderWidth: 3, borderColor: C.cyan, shadowColor: C.cyan, shadowOpacity: 1, shadowRadius: 18, backgroundColor: 'rgba(79,227,255,.12)' },
  tourCard: { position: 'absolute', left: 16, right: 16, padding: 14, borderRadius: 24, backgroundColor: 'rgba(12,20,58,.98)', borderWidth: 1, borderColor: 'rgba(92,225,255,.5)' },
  tourText: { flex: 1, marginRight: 8, marginBottom: 6, padding: 10, borderRadius: 16, backgroundColor: 'rgba(79,227,255,.08)' },
  heroGlow: { position: 'absolute', bottom: 8, width: 120, height: 22, borderRadius: 60, backgroundColor: C.cyan, opacity: .35, shadowColor: C.cyan, shadowOpacity: 1, shadowRadius: 20 },
  pm: { maxWidth: '88%', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16 },
  pmMe: { backgroundColor: 'rgba(79,227,255,.16)', borderWidth: 1, borderColor: 'rgba(79,227,255,.35)', borderBottomLeftRadius: 4 },
  pmO: { backgroundColor: 'rgba(20,30,70,.94)', borderWidth: 1, borderColor: C.line, borderBottomRightRadius: 4 },
  inRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, paddingTop: 8, borderTopWidth: 1, borderTopColor: C.line },
  in: { flex: 1, height: 46, borderRadius: 23, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(6,10,30,.85)', color: C.text, paddingHorizontal: 16, fontFamily: F.fa, fontSize: 14, textAlign: 'right', writingDirection: 'rtl', marginLeft: 8 },
  send: { width: 46, height: 46, borderRadius: 23, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(79,227,255,.18)', borderWidth: 1, borderColor: C.cyan },
});
