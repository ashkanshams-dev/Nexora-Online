// Arena: ranked ladder by arena points (+30 win +5/streak, −20 loss), streaks, find-match buttons.
import React, { useCallback, useEffect, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI2 } from '../game/assets';
import { Btn, Img, Panel, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { Mode, Room, errFa, rpc, supabase } from '../net/supabase';
import { useNav } from '../nav';
import { Empty, ErrorState, Header, S, Skeleton, TS } from './ui';
import { LbItem, LbRow } from './Ranks';
import { useOracle } from '../oracle/Oracle';

export default function Arena({ onBack, onRoom, toast }: { onBack: () => void; onRoom: (r: Room) => void; toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets(); const { profile, uid } = useAuth(); const nav = useNav();
  const [rows, setRows] = useState<(LbRow & { arena_points: number })[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<Mode | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const oracle = useOracle();
  const load = useCallback(async () => {
    const { data, error } = await supabase.from('profiles').select('id, username, avatar, level, xp, rating, league, wins, losses, draws, trophies, arena_points').gt('arena_points', 0).order('arena_points', { ascending: false }).limit(50);
    if (error) { setErr(errFa(error)); return; }
    setErr(null); setRows((data || []).map((r: any, i: number) => ({ ...r, rank: i + 1 })));
  }, []);
  useEffect(() => { load(); }, [load]);
  const find = async (m: Mode) => {
    if (busy) return; setBusy(m); oracle.react('search');
    try { const r = await rpc<Room>('quick_match', { p_mode: m, p_kind: 'arena' }); sfx('join'); buzz('medium'); onRoom(r); }
    catch (e) { toast(errFa(e), 'err'); } finally { setBusy(null); }
  };
  const header = (
    <View style={{ paddingHorizontal: S.l }}>
      <Panel style={{ padding: S.l }} accent={C.violet} glow>
        <LinearGradient colors={['rgba(163,91,255,.25)', 'transparent']} style={StyleSheet.absoluteFill} />
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
          <Img src={UI2.x_crown} style={{ width: 64, height: 64 }} />
          <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
            <T s="امتیاز آرنا" style={{ fontSize: TS.small, color: C.dim }} />
            <T s={fa(profile?.arena_points ?? 0)} style={{ fontFamily: F.title, fontSize: 32, color: '#e2c8ff' }} />
          </View>
          <View style={{ alignItems: 'center' }}>
            <T s={`🔥 ${fa(profile?.win_streak ?? 0)}`} style={{ fontFamily: F.title, fontSize: 18, color: C.orange }} />
            <T s="برد پیاپی" style={{ fontSize: TS.tiny, color: C.dim }} />
            <T s={`بهترین ${fa(profile?.best_streak ?? 0)}`} style={{ fontSize: TS.tiny, color: C.dim2, marginTop: 2 }} />
          </View>
        </View>
        <T s="برد: ۳۰+ و ۵+ برای هر برد پیاپی · باخت: ۲۰−" style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right', marginTop: S.s }} />
        <View style={{ flexDirection: 'row-reverse', marginTop: S.m }}>
          {(['1v1', '2v2', '3v3'] as Mode[]).map((m, i) => (
            <Btn key={m} label={busy === m ? '…' : m.toUpperCase()} sub="یافتن حریف" small colors={i === 0 ? G.violet : i === 1 ? G.primary : G.gold} onPress={() => find(m)} disabled={!!busy} style={{ flex: 1, marginLeft: i < 2 ? S.s : 0 }} />
          ))}
        </View>
      </Panel>
      <T s="نردبان آرنا" style={{ fontFamily: F.bold, fontSize: TS.h, textAlign: 'right', marginTop: S.l, marginBottom: S.s }} />
    </View>
  );
  return (
    <View style={{ flex: 1 }}>
      <Header title="آرنا" en="ARENA LADDER" accent={C.violet} onBack={onBack} />
      <FlatList data={rows || []} keyExtractor={r => r.id} ListHeaderComponent={header}
        renderItem={({ item }) => <View style={{ paddingHorizontal: S.l }}><LbItem r={item} mine={item.id === uid} metric={item.arena_points} metricLabel="آرنا" onPress={() => nav.openProfile(item.id)} /></View>}
        ListEmptyComponent={err ? <ErrorState msg={err} onRetry={load} /> : !rows ? <Skeleton rows={6} h={58} /> : <Empty img={UI2.x_crown} title="هنوز کسی امتیاز آرنا ندارد" sub="اولین برد آرنا مال تو باشد!" />}
        contentContainerStyle={{ paddingTop: ins.top + 76, paddingBottom: ins.bottom + S.xl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} tintColor={C.cyan} progressViewOffset={ins.top + 70} />}
        showsVerticalScrollIndicator={false} />
    </View>
  );
}
