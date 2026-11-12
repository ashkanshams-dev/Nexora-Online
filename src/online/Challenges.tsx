// Daily challenges (4 per Tehran day): progress, claim with animation, reset countdown.
import React, { useCallback, useEffect, useState } from 'react';
import { RefreshControl, ScrollView, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI2 } from '../game/assets';
import { Bar, Btn, Img, Panel, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { errFa, rpc, supabase } from '../net/supabase';
import { useAuth } from '../net/auth';
import { Empty, ErrorState, Header, S, Skeleton, TS } from './ui';

export type Challenge = { def_id: string; progress: number; claimed: boolean; title_fa: string; target: number; reward_gems: number; reward_xp: number };
let defsCache: Record<string, any> | null = null;

// next midnight in Asia/Tehran (UTC+03:30, no DST)
export function msToTehranMidnight(now = Date.now()) {
  const off = 3.5 * 3600000, day = 86400000;
  return Math.ceil((now + off + 1) / day) * day - off - now;
}

export async function loadChallenges(): Promise<Challenge[]> {
  const rows = await rpc<any[]>('get_daily_challenges');
  if (!defsCache) { const { data } = await supabase.from('challenge_defs').select('*'); defsCache = {}; for (const d of data || []) defsCache[(d as any).id] = d; }
  return (rows || []).map(r => ({ ...r, ...(defsCache![r.def_id] || { title_fa: r.def_id, target: 1, reward_gems: 0, reward_xp: 0 }), def_id: r.def_id, progress: r.progress, claimed: r.claimed }));
}

export function useChallenges() {
  const { uid } = useAuth();
  const [list, setList] = useState<Challenge[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const load = useCallback(async () => {
    if (!uid) return;
    try { setList(await loadChallenges()); setErr(null); } catch (e) { setErr(errFa(e)); }
  }, [uid]);
  useEffect(() => {
    if (!uid) return;
    load();
    const ch = supabase.channel(`uc:${uid}`).on('postgres_changes', { event: '*', schema: 'public', table: 'user_challenges', filter: `user_id=eq.${uid}` }, () => load()).subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [uid, load]);
  return { list, err, load, setList };
}

export default function Challenges({ onBack, toast }: { onBack: () => void; toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets();
  const { list, err, load, setList } = useChallenges();
  const [left, setLeft] = useState(msToTehranMidnight());
  const [refreshing, setRefreshing] = useState(false);
  useEffect(() => { const id = setInterval(() => setLeft(msToTehranMidnight()), 1000); return () => clearInterval(id); }, []);
  const h = Math.floor(left / 3600000), m = Math.floor((left % 3600000) / 60000), s = Math.floor((left % 60000) / 1000);
  const claim = async (c: Challenge) => {
    try {
      const r = await rpc<{ gems: number; xp: number }>('claim_challenge', { p_def: c.def_id });
      sfx('win'); buzz('success'); toast(`+${fa(r.gems)} الماس · +${fa(r.xp)} XP`, 'ok');
      setList(l => l && l.map(x => (x.def_id === c.def_id ? { ...x, claimed: true } : x)));
    } catch (e) { toast(errFa(e), 'err'); }
  };
  return (
    <View style={{ flex: 1 }}>
      <Header title="چالش‌های روزانه" en="DAILY CHALLENGES" accent={C.green} onBack={onBack} />
      <ScrollView contentContainerStyle={{ paddingTop: ins.top + 76, paddingHorizontal: S.l, paddingBottom: ins.bottom + S.xl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} tintColor={C.cyan} progressViewOffset={ins.top + 70} />}>
        <Panel style={{ padding: S.m, flexDirection: 'row-reverse', alignItems: 'center' }} accent={C.green}>
          <Img src={UI2.c_calendar} style={{ width: 48, height: 48 }} />
          <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
            <T s="چالش‌های امروز" style={{ fontFamily: F.title, fontSize: TS.h }} />
            <T s={`تازه‌سازی تا ${fa(h)}:${String(m).padStart(2, '0').replace(/\d/g, d => '۰۱۲۳۴۵۶۷۸۹'[+d])}:${String(s).padStart(2, '0').replace(/\d/g, d => '۰۱۲۳۴۵۶۷۸۹'[+d])}`} style={{ fontSize: TS.cap, color: C.dim, marginTop: 2 }} />
          </View>
        </Panel>
        <View style={{ marginTop: S.m }}>
          {err ? <ErrorState msg={err} onRetry={load} /> : !list ? <Skeleton rows={4} h={96} /> : !list.length ? <Empty title="امروز چالشی نیست" /> :
            list.map((c, i) => <ChallengeCard key={c.def_id} c={c} i={i} onClaim={() => claim(c)} />)}
        </View>
      </ScrollView>
    </View>
  );
}

export function ChallengeCard({ c, onClaim, compact }: { c: Challenge; i?: number; onClaim: () => void; compact?: boolean }) {
  const done = c.progress >= c.target;
  const sc = useSharedValue(1);
  const a = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));
  const claim = () => { sc.value = withSequence(withTiming(1.06, { duration: 120 }), withSpring(1, { damping: 8 })); onClaim(); };
  return (
    <Animated.View style={[{ marginBottom: S.s }, a]}>
      <Panel style={{ padding: compact ? S.s : S.m, flexDirection: 'row-reverse', alignItems: 'center', opacity: c.claimed ? .6 : 1 }} accent={done && !c.claimed ? C.green : 'transparent'} glow={done && !c.claimed}>
        <Img src={c.claimed ? UI2.x_medal : done ? UI2.x_star : UI2.x_ball} style={{ width: compact ? 36 : 44, height: compact ? 36 : 44 }} />
        <View style={{ flex: 1, marginHorizontal: S.s }}>
          <T s={c.title_fa} n={2} style={{ fontFamily: F.bold, fontSize: compact ? TS.small : TS.body, textAlign: 'right' }} />
          <View style={{ marginTop: S.xs }}><Bar v={Math.min(1, c.progress / Math.max(1, c.target))} h={6} color={done ? C.green : C.cyan} /></View>
          <T s={`${fa(Math.min(c.progress, c.target))}/${fa(c.target)} · 💎${fa(c.reward_gems)} · ${fa(c.reward_xp)}XP`} style={{ fontSize: TS.tiny, color: C.dim, textAlign: 'right', marginTop: 2 }} />
        </View>
        <View style={{ width: 76 }}>
          {c.claimed ? <T s="✓ گرفتی" style={{ fontSize: TS.cap, color: C.green, textAlign: 'center' }} />
            : done ? <Btn small label="دریافت" colors={G.green} onPress={claim} />
              : <T s="در جریان" style={{ fontSize: TS.cap, color: C.dim, textAlign: 'center' }} />}
        </View>
      </Panel>
    </Animated.View>
  );
}

// Home card: today's challenges at a glance (only when signed in)
export function HomeChallenges({ toast, onAll }: { toast: (m: string, k?: string) => void; onAll: () => void }) {
  const { uid } = useAuth();
  const { list, setList } = useChallenges();
  const [left, setLeft] = useState(msToTehranMidnight());
  useEffect(() => { const id = setInterval(() => setLeft(msToTehranMidnight()), 60000); return () => clearInterval(id); }, []);
  if (!uid || !list || !list.length) return null;
  const done = list.filter(c => c.claimed).length;
  const claim = async (c: Challenge) => {
    try { const r = await rpc<{ gems: number; xp: number }>('claim_challenge', { p_def: c.def_id }); sfx('win'); buzz('success'); toast(`+${fa(r.gems)} الماس · +${fa(r.xp)} XP`, 'ok'); setList(l => l && l.map(x => (x.def_id === c.def_id ? { ...x, claimed: true } : x))); }
    catch (e) { toast(errFa(e), 'err'); }
  };
  return (
    <Panel style={{ padding: S.m }} accent={C.green}>
      <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginBottom: S.s }}>
        <Img src={UI2.c_calendar} style={{ width: 34, height: 34 }} />
        <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
          <T s="چالش‌های امروز" style={{ fontFamily: F.bold, fontSize: TS.body }} />
          <T s={`${fa(done)}/${fa(list.length)} انجام شد · تازه‌سازی ${fa(Math.floor(left / 3600000))} ساعت دیگر`} style={{ fontSize: TS.tiny, color: C.dim }} />
        </View>
        <Btn label="همه" small colors={G.dark} onPress={onAll} style={{ width: 72 }} />
      </View>
      {list.slice(0, 4).map(c => <ChallengeCard key={c.def_id} c={c} onClaim={() => claim(c)} compact />)}
    </Panel>
  );
}
