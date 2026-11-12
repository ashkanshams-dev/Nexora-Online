// Leaderboard (top 100 by rating, my rank highlighted) + league ladder with season countdown & rewards.
import React, { memo, useCallback, useEffect, useState } from 'react';
import { FlatList, RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI, UI2 } from '../game/assets';
import { Bar, Btn, Img, Panel, Press, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { errFa, rpc, supabase } from '../net/supabase';
import { useNav } from '../nav';
import { Avatar, Badge, Empty, ErrorState, Header, LEAGUE_IMG, S, Skeleton, TS, Tabs, useLeagues } from './ui';

export type LbRow = { id: string; username: string; avatar: string; level: number; xp: number; rating: number; league: string; wins: number; losses: number; draws: number; trophies: number; rank: number };

export default function Ranks({ onBack, toast, tab: tab0 }: { onBack: () => void; toast: (m: string, k?: string) => void; tab?: 'top' | 'leagues' }) {
  const ins = useSafeAreaInsets();
  const [tab, setTab] = useState<'top' | 'leagues'>(tab0 || 'top');
  return (
    <View style={{ flex: 1 }}>
      <Header title={tab === 'top' ? 'رده‌بندی' : 'لیگ‌ها و فصل'} en={tab === 'top' ? 'LEADERBOARD' : 'LEAGUES · SEASON'} accent={C.gold} onBack={onBack} />
      <View style={{ paddingTop: ins.top + 76, paddingHorizontal: S.l, paddingBottom: S.s }}>
        <Tabs items={[['top', 'برترین‌ها'], ['leagues', 'لیگ‌ها']]} value={tab} onChange={setTab} />
      </View>
      {tab === 'top' ? <Leaderboard /> : <Leagues toast={toast} />}
    </View>
  );
}

function Leaderboard() {
  const ins = useSafeAreaInsets(); const { uid } = useAuth(); const nav = useNav();
  const [rows, setRows] = useState<LbRow[] | null>(null);
  const [me, setMe] = useState<LbRow | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const load = useCallback(async () => {
    const [a, b] = await Promise.all([
      supabase.from('leaderboard').select('*').order('rank').limit(100),
      uid ? supabase.from('leaderboard').select('*').eq('id', uid).maybeSingle() : Promise.resolve({ data: null, error: null } as any),
    ]);
    if (a.error) { setErr(errFa(a.error)); return; }
    setErr(null); setRows(a.data as LbRow[]); setMe((b.data as LbRow) || null);
  }, [uid]);
  useEffect(() => { load(); }, [load]);
  const inTop = !!me && !!rows?.some(r => r.id === me.id);
  return (
    <FlatList
      data={rows || []} keyExtractor={r => r.id}
      ListHeaderComponent={me && !inTop ? <View style={{ paddingHorizontal: S.l, marginBottom: S.s }}><LbItem r={me} mine onPress={() => {}} /></View> : undefined}
      renderItem={({ item }) => <View style={{ paddingHorizontal: S.l }}><LbItem r={item} mine={item.id === uid} onPress={() => nav.openProfile(item.id)} /></View>}
      ListEmptyComponent={err ? <ErrorState msg={err} onRetry={load} /> : !rows ? <Skeleton rows={8} h={60} /> : <Empty title="هنوز کسی در رده‌بندی نیست" />}
      contentContainerStyle={{ paddingBottom: ins.bottom + S.xl }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} tintColor={C.cyan} />}
      initialNumToRender={14} windowSize={9} getItemLayout={(_, i) => ({ length: 64, offset: 64 * i, index: i })} showsVerticalScrollIndicator={false} />
  );
}

export const LbItem = memo(function LbItem({ r, mine, onPress, metric, metricLabel }: { r: LbRow & { arena_points?: number }; mine: boolean; onPress: () => void; metric?: number; metricLabel?: string }) {
  const medal = r.rank <= 3 ? [C.gold, '#d6e2f0', '#e0954a'][r.rank - 1] : null;
  return (
    <Press onPress={onPress} scaleTo={.98}>
      <View style={[st.row, mine && { borderColor: C.cyan, backgroundColor: 'rgba(79,227,255,.12)' }]}>
        <View style={[st.rank, medal ? { backgroundColor: medal + '33', borderColor: medal } : null]}><T s={fa(r.rank)} style={{ fontFamily: F.title, fontSize: 13, color: medal || C.dim }} /></View>
        <Avatar avatar={r.avatar} size={40} ring={medal || C.line} />
        <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
          <T s={r.username + (mine ? ' (تو)' : '')} n={1} style={{ fontFamily: F.bold, fontSize: TS.body }} />
          <T s={`سطح ${fa(r.level)} · ${fa(r.wins)} برد`} style={{ fontSize: TS.tiny, color: C.dim }} />
        </View>
        <Img src={(UI as any)[LEAGUE_IMG[r.league] || 'medal_bronze']} style={{ width: 30, height: 30 }} />
        <View style={{ alignItems: 'center', width: 56 }}>
          <T s={fa(metric ?? r.rating)} style={{ fontFamily: F.title, fontSize: 14, color: C.gold }} />
          <T s={metricLabel || 'امتیاز'} style={{ fontSize: 9, color: C.dim }} />
        </View>
      </View>
    </Press>
  );
});

type Season = { id: number; name: string; starts_at: string; ends_at: string };
function Leagues({ toast }: { toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets(); const { profile } = useAuth();
  const leagues = useLeagues();
  const [season, setSeason] = useState<Season | null>(null);
  const [rewards, setRewards] = useState<Record<string, number>>({});
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    rpc<Season>('current_season').then(setSeason, () => {});
    supabase.from('season_rewards').select('*').then(({ data }) => { const m: Record<string, number> = {}; for (const r of data || []) m[(r as any).league] = (r as any).gems; setRewards(m); }, () => {});
    const id = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(id);
  }, []);
  const left = season ? Math.max(0, new Date(season.ends_at).getTime() - now) : 0;
  const d = Math.floor(left / 86400000), h = Math.floor((left % 86400000) / 3600000);
  const rating = profile?.rating ?? 0;
  const list = (leagues || []).slice().sort((a, b) => a.sort - b.sort);
  const cur = list.filter(l => l.min_rating <= rating).pop();
  const nxt = list.find(l => l.min_rating > rating);
  const claim = async () => {
    setBusy(true);
    try { const r = await rpc<{ gems: number }>('claim_season_reward'); sfx('win'); buzz('success'); toast(`+${fa(r.gems)} الماس جایزه‌ی فصل`, 'ok'); }
    catch (e) { toast(errFa(e), 'err'); } finally { setBusy(false); }
  };
  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: S.l, paddingBottom: ins.bottom + S.xl }} showsVerticalScrollIndicator={false}>
      <Panel style={{ padding: S.m }} accent={C.violet} glow>
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
          <Img src={UI2.c_calendar} style={{ width: 48, height: 48 }} />
          <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
            <T s={season?.name || 'فصل جاری'} style={{ fontFamily: F.title, fontSize: TS.h }} />
            <T s={season ? `${fa(d)} روز و ${fa(h)} ساعت تا پایان فصل` : '…'} style={{ fontSize: TS.cap, color: C.dim, marginTop: 2 }} />
          </View>
        </View>
        <T s="در پایان هر فصل بر اساس لیگت الماس می‌گیری. جایزه‌ی فصل قبل را این‌جا دریافت کن." style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right', marginTop: S.s }} />
        <Btn label={busy ? '…' : 'دریافت جایزه‌ی فصل قبل'} small colors={G.violet} onPress={claim} disabled={busy} style={{ marginTop: S.s }} />
      </Panel>
      {profile && cur ? (
        <Panel style={{ padding: S.m, marginTop: S.m }} accent={cur.color}>
          <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
            <Img src={(UI as any)[LEAGUE_IMG[cur.id]]} style={{ width: 56, height: 56 }} />
            <View style={{ flex: 1, marginRight: S.m }}>
              <T s={`لیگ ${cur.name_fa}`} style={{ fontFamily: F.title, fontSize: TS.h, textAlign: 'right', color: cur.color }} />
              <View style={{ marginTop: S.s }}><Bar v={nxt ? (rating - cur.min_rating) / (nxt.min_rating - cur.min_rating) : 1} color={cur.color} color2={C.indigo} /></View>
              <T s={nxt ? `${fa(rating)} / ${fa(nxt.min_rating)} تا لیگ ${nxt.name_fa}` : `${fa(rating)} · بالاترین لیگ!`} style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right', marginTop: S.xs }} />
            </View>
          </View>
        </Panel>
      ) : null}
      <T s="نردبان لیگ‌ها" style={{ fontFamily: F.bold, fontSize: TS.h, textAlign: 'right', marginTop: S.l, marginBottom: S.s }} />
      {!leagues ? <Skeleton rows={7} h={64} /> : list.slice().reverse().map(l => {
        const on = cur?.id === l.id, reached = rating >= l.min_rating;
        return (
          <View key={l.id} style={[st.row, { height: 68 }, on && { borderColor: l.color, backgroundColor: l.color + '1f' }]}>
            <Img src={(UI as any)[LEAGUE_IMG[l.id]]} style={{ width: 44, height: 44, opacity: reached ? 1 : .4 }} />
            <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
              <T s={l.name_fa} style={{ fontFamily: F.bold, fontSize: TS.body, color: reached ? l.color : C.dim }} />
              <T s={`از ${fa(l.min_rating)} امتیاز`} style={{ fontSize: TS.tiny, color: C.dim }} />
            </View>
            {on ? <Badge label="لیگ تو" color={l.color} /> : null}
            <View style={{ alignItems: 'center', width: 64 }}>
              <T s={`💎 ${fa(rewards[l.id] ?? 0)}`} style={{ fontFamily: F.bold, fontSize: TS.small, color: '#9fd8ff' }} />
              <T s="جایزه‌ی فصل" style={{ fontSize: 9, color: C.dim }} />
            </View>
          </View>
        );
      })}
    </ScrollView>
  );
}

const st = StyleSheet.create({
  row: { flexDirection: 'row-reverse', alignItems: 'center', height: 58, paddingHorizontal: S.s, marginBottom: 6, borderRadius: 16, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(10,16,44,.85)' },
  rank: { width: 34, height: 34, borderRadius: 17, borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center', marginLeft: S.s },
});
