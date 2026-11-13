// Online hub: profile strip, quick match, create / join by code, live room list.
import React, { memo, useCallback, useEffect, useRef, useState } from 'react';
import { useNav } from '../nav';
import { FlatList, RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI, UI2 } from '../game/assets';
import { Btn, Enter, Img, Panel, Press, Segment, T, Toggle } from '../ui/kit';
import { Sheet, SheetHandle } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { Mode, Room, RoomListRow, errFa, levelProgress, rpc, supabase } from '../net/supabase';
import { Avatar, Badge, Empty, ErrorState, Field, Header, LEAGUE_IMG, S, Skeleton, TS, Tabs, useLeagues } from './ui';
import { FieldPicker, ruleToSettings } from './Lobby';
import { ruleLabel } from './OnlineMatch';
import { Bar } from '../ui/kit';
import { useOracle } from '../oracle/Oracle';

export type HubNav = 'tours' | 'ranks' | 'arena' | 'challenges';
type Props = { onBack: () => void; onRoom: (r: Room) => void; onNav: (n: HubNav) => void; toast: (m: string, k?: string) => void };

const MODES: Mode[] = ['1v1', '2v2', '3v3'];
const MODE_FA: Record<Mode, string> = { '1v1': 'تک به تک', '2v2': '۲ به ۲', '3v3': '۳ به ۳' };
export const KIND_FA: Record<string, [string, string]> = { casual: ['دوستانه', C.green], quick: ['سریع', C.cyan], arena: ['آرنا', C.violet], tournament: ['تورنمنت', C.orange] };

export default function Hub({ onBack, onRoom, onNav, toast }: Props) {
  const ins = useSafeAreaInsets();
  const { profile } = useAuth();
  const oracle = useOracle();
  const [rows, setRows] = useState<RoomListRow[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [filter, setFilter] = useState<'all' | Mode>('all');
  const [busy, setBusy] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [sheet, setSheet] = useState(false);
  const sheetRef = useRef<SheetHandle>(null);
  const t = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from('room_list').select('*').order('created_at', { ascending: false }).limit(60);
    if (error) { setErr(errFa(error)); return; }
    setErr(null); setRows((data || []) as RoomListRow[]);
  }, []);
  useEffect(() => {
    load();
    const soon = () => { if (t.current) clearTimeout(t.current); t.current = setTimeout(load, 600); };
    const ch = supabase.channel('hub:rooms')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms' }, soon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'room_players' }, soon)
      .subscribe();
    const poll = setInterval(load, 20000);
    return () => { if (t.current) clearTimeout(t.current); clearInterval(poll); supabase.removeChannel(ch); };
  }, [load]);
  const refresh = async () => { setRefreshing(true); await load(); setRefreshing(false); };

  const act = async (key: string, fn: () => Promise<Room>) => {
    if (busy) return; setBusy(key);
    try { const r = await fn(); sfx('join'); buzz('medium'); onRoom(r); }
    catch (e) { toast(errFa(e), 'err'); buzz('heavy'); }
    finally { setBusy(null); }
  };
  const quick = (m: Mode, kind: 'quick' | 'arena' = 'quick') => { oracle.react('search'); return act(kind + m, () => rpc<Room>('quick_match', { p_mode: m, p_kind: kind })); };
  const join = (id: string, spectate: boolean) => act((spectate ? 'w' : 'j') + id, () => rpc<Room>('join_room', { p_room: id, p_spectate: spectate }));
  const joinCode = () => {
    const c = code.trim().toUpperCase();
    if (c.length !== 6) { toast('کد اتاق ۶ کاراکتر است', 'err'); return; }
    act('code', () => rpc<Room>('join_room', { p_code: c }));
  };

  const data = (rows || []).filter(r => filter === 'all' || r.mode === filter);
  const lp = profile ? levelProgress(profile.xp) : null;

  const header = (
    <View>
      {/* my online card */}
      {profile && lp ? (
        <Enter i={0} style={{ paddingHorizontal: S.l }}>
          <Press onPress={() => onNav('ranks')} scaleTo={.98}>
            <Panel style={{ padding: S.m, flexDirection: 'row-reverse', alignItems: 'center' }} accent={C.gold}>
              <Avatar avatar={profile.equipped_disc || profile.avatar} url={profile.avatar_url} size={52} ring={C.gold} />
              <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
                <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
                  <T s={profile.username} n={1} style={{ fontFamily: F.bold, fontSize: TS.h, maxWidth: 150 }} />
                  <Badge label={`سطح ${fa(profile.level)}`} color={C.gold} />
                </View>
                <View style={{ alignSelf: 'stretch', marginTop: S.s }}><Bar v={lp.frac} color={C.cyan} color2={C.violet} h={6} /></View>
                <T s={`${fa(lp.cur)} / ${fa(lp.need)} XP · امتیاز ${fa(profile.rating)}`} style={{ fontSize: TS.tiny, color: C.dim, marginTop: 2 }} />
              </View>
              <Img src={(UI as any)[LEAGUE_IMG[profile.league] || 'medal_bronze']} style={{ width: 48, height: 48 }} />
            </Panel>
          </Press>
        </Enter>
      ) : null}

      {/* quick match */}
      <Enter i={1} style={{ paddingHorizontal: S.l, marginTop: S.m }}>
        <Panel style={{ padding: S.m }} accent={C.cyan} glow>
          <LinearGradient colors={['rgba(79,227,255,.14)', 'transparent']} style={StyleSheet.absoluteFill} />
          <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginBottom: S.s }}>
            <Img src={UI2.x_ball} style={{ width: 36, height: 36 }} />
            <View style={{ marginRight: S.s, flex: 1, alignItems: 'flex-end' }}>
              <T s="مسابقه‌ی سریع" style={{ fontFamily: F.title, fontSize: TS.h }} />
              <T s="هم‌سطح‌ترین حریف آنلاین را پیدا کن" style={{ fontSize: TS.cap, color: C.dim }} />
            </View>
          </View>
          <View style={{ flexDirection: 'row-reverse' }}>
            {MODES.map((m, i) => (
              <Btn key={m} label={busy === 'quick' + m ? '…' : m.toUpperCase()} sub={MODE_FA[m]} small onPress={() => quick(m)} disabled={!!busy}
                colors={i === 0 ? G.primary : i === 1 ? G.violet : G.gold} style={{ flex: 1, marginLeft: i < 2 ? S.s : 0 }} />
            ))}
          </View>
        </Panel>
      </Enter>

      {/* shortcuts */}
      <View style={{ flexDirection: 'row-reverse', paddingHorizontal: S.l, marginTop: S.m }}>
        {([['arena', 'آرنا', UI2.x_crown, C.violet], ['tours', 'تورنمنت', UI2.x_trophy, C.orange], ['ranks', 'رده‌بندی', UI2.x_medal, C.gold], ['challenges', 'چالش‌ها', UI2.c_calendar, C.green]] as const).map(([k, l, img, c], i) => (
          <Press key={k} onPress={() => onNav(k)} style={[s.tile, { borderColor: c + '66', marginLeft: i < 3 ? S.s : 0 }]}>
            <LinearGradient colors={[c + '33', 'rgba(8,12,34,.9)']} style={StyleSheet.absoluteFill} />
            <Img src={img} style={{ width: 36, height: 36 }} />
            <T s={l} n={1} style={{ fontFamily: F.bold, fontSize: TS.cap, marginTop: 2 }} />
          </Press>
        ))}
      </View>

      {/* create / join */}
      <View style={{ flexDirection: 'row-reverse', paddingHorizontal: S.l, marginTop: S.m, alignItems: 'flex-start' }}>
        <Btn label="ساخت اتاق" small onPress={() => setSheet(true)} colors={G.green} style={{ width: 128, marginLeft: S.s }} />
        <View style={{ flex: 1, flexDirection: 'row-reverse' }}>
          <Field value={code} onChangeText={v => setCode(v.replace(/[^a-zA-Z0-9]/g, '').toUpperCase().slice(0, 6))} placeholder="کد ۶ رقمی" autoCapitalize="characters"
            maxLength={6} style={{ height: 44, textAlign: 'center', letterSpacing: 2, fontFamily: F.head }} onSubmitEditing={joinCode} returnKeyType="go" />
        </View>
        <Press onPress={joinCode} style={s.go} disabled={busy === 'code'}><T s="ورود" style={{ fontFamily: F.bold, fontSize: TS.small }} /></Press>
      </View>

      <View style={{ paddingHorizontal: S.l, marginTop: S.s, marginBottom: S.s }}>
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginBottom: S.s }}>
          <T s="اتاق‌های باز" style={{ fontFamily: F.bold, fontSize: TS.h }} />
          <View style={{ flex: 1 }} />
          <T s={rows ? `${fa(data.length)} اتاق` : ''} style={{ fontSize: TS.cap, color: C.dim }} />
        </View>
        <Tabs items={[['all', 'همه'], ['1v1', '1v1'], ['2v2', '2v2'], ['3v3', '3v3']]} value={filter} onChange={setFilter} />
      </View>
    </View>
  );

  return (
    <View style={{ flex: 1 }}>
      <Header title="آنلاین" en="ONLINE ARENA" onBack={onBack} />
      <FlatList
        data={rows ? data : []}
        keyExtractor={r => r.id}
        renderItem={({ item }) => <RoomRow r={item} busy={busy} onJoin={join} />}
        ListHeaderComponent={header}
        ListEmptyComponent={err ? <ErrorState msg={err} onRetry={load} /> : !rows ? <Skeleton rows={4} /> :
          <Empty img={UI2.x_ball} title="فعلاً اتاقی باز نیست" sub="یک اتاق بساز و دوستانت را با کد دعوت کن" action="ساخت اتاق" onAction={() => setSheet(true)} />}
        contentContainerStyle={{ paddingTop: ins.top + 76, paddingBottom: ins.bottom + S.xl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} tintColor={C.cyan} colors={[C.cyan]} progressViewOffset={ins.top + 70} />}
        keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false} initialNumToRender={8} windowSize={7} removeClippedSubviews
      />
      {sheet ? (
        <Sheet ref={sheetRef} onClosed={() => setSheet(false)} title="ساخت اتاق" en="CREATE ROOM" accent={C.green} height={.88}>
          <CreateRoom busy={busy === 'create'} onCreate={(a) => act('create', async () => { const r = await rpc<Room>('create_room', a); sheetRef.current?.close(); return r; })} />
        </Sheet>
      ) : null}
    </View>
  );
}

const RoomRow = memo(function RoomRow({ r, busy, onJoin }: { r: RoomListRow; busy: string | null; onJoin: (id: string, spectate: boolean) => void }) {
  const full = r.players >= r.capacity, playing = r.status === 'playing'; const nav = useNav();
  const [kl, kc] = KIND_FA[r.kind] || KIND_FA.casual;
  return (
    <View style={{ paddingHorizontal: S.l, marginBottom: S.s }}>
      <Panel style={{ padding: S.m }} accent="transparent">
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
          <Press onPress={() => nav.openProfile(r.host)}><Avatar avatar={r.host_avatar} url={r.host_avatar_url} size={44} ring={playing ? C.red : C.cyan} /></Press>
          <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
            <T s={r.name} n={1} style={{ fontFamily: F.bold, fontSize: TS.body }} />
            <T s={`${r.host_name} · سطح ${fa(r.host_level)} · ${ruleLabel(r.settings)}`} n={1} style={{ fontSize: TS.cap, color: C.dim, marginTop: 2 }} />
            <View style={{ flexDirection: 'row-reverse', marginTop: S.xs }}>
              <Badge label={r.mode.toUpperCase()} color={C.sky} />
              <Badge label={kl} color={kc} />
              {playing ? <Badge label="زنده" color={C.red} live /> : <Badge label="در انتظار" color={C.green} />}
            </View>
          </View>
          <View style={{ alignItems: 'center', width: 64 }}>
            <T s={`${fa(r.players)}/${fa(r.capacity)}`} style={{ fontFamily: F.title, fontSize: TS.h, color: full ? C.orange : C.text }} />
            <T s={`👁 ${fa(r.spectators)}`} style={{ fontSize: TS.tiny, color: C.dim }} />
          </View>
        </View>
        <View style={{ flexDirection: 'row-reverse', marginTop: S.s }}>
          {!playing && !full ? <Btn label={busy === 'j' + r.id ? '…' : 'ورود'} small onPress={() => onJoin(r.id, false)} disabled={!!busy} style={{ flex: 1, marginLeft: S.s }} /> : null}
          <Btn label={busy === 'w' + r.id ? '…' : 'تماشا'} small onPress={() => onJoin(r.id, true)} disabled={!!busy} colors={G.dark} style={{ flex: 1 }} />
        </View>
      </Panel>
    </View>
  );
});

function CreateRoom({ onCreate, busy }: { onCreate: (a: any) => void; busy: boolean }) {
  const [name, setName] = useState('');
  const [mode, setMode] = useState<Mode>('1v1');
  const [priv, setPriv] = useState(false);
  const [ranked, setRanked] = useState(true);
  const [voice, setVoice] = useState(true);
  const [rule, setRule] = useState('g3');
  const [turn, setTurn] = useState(15);
  const [field, setField] = useState(0);
  const row = (label: string, sub: string, v: boolean, set: (b: boolean) => void) => (
    <View style={s.optRow}>
      <View style={{ flex: 1, alignItems: 'flex-end', marginLeft: S.m }}>
        <T s={label} style={{ fontFamily: F.bold, fontSize: TS.body }} />
        <T s={sub} style={{ fontSize: TS.cap, color: C.dim }} />
      </View>
      <Toggle on={v} onChange={set} />
    </View>
  );
  return (
    <ScrollView contentContainerStyle={{ padding: S.l, paddingBottom: S.xl * 2 }} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
      <Field label="نام اتاق" value={name} onChangeText={setName} placeholder="مثلاً: فینال کهکشانی" maxLength={40} />
      <T s="حالت" style={s.lbl} />
      <Segment value={mode} onChange={setMode} items={MODES.map(m => [m, MODE_FA[m]])} />
      <T s="قانون" style={s.lbl} />
      <Segment value={rule} onChange={setRule} items={[['g3', 'تا ۳ گل'], ['g5', 'تا ۵ گل'], ['t3', '۳ دقیقه'], ['t5', '۵ دقیقه']]} accent={C.violet} />
      <T s="زمان هر نوبت" style={s.lbl} />
      <Segment value={turn} onChange={setTurn} items={[[10, '۱۰ث'], [15, '۱۵ث'], [20, '۲۰ث'], [0, 'بدون']]} accent={C.green} />
      <T s="زمین" style={s.lbl} />
      <FieldPicker value={field} onChange={setField} />
      <View style={{ marginTop: S.m }}>
        {row('خصوصی', 'فقط با کد اتاق می‌شود وارد شد', priv, setPriv)}
        {row('رتبه‌ای', 'نتیجه روی امتیاز و لیگ اثر دارد', ranked, setRanked)}
        {row('چت صوتی', 'بازیکن‌ها می‌توانند صحبت کنند', voice, setVoice)}
      </View>
      <Btn label={busy ? 'در حال ساخت…' : 'ساخت اتاق'} disabled={busy} colors={G.green} style={{ marginTop: S.l }}
        onPress={() => onCreate({ p_mode: mode, p_name: name.trim() || null, p_private: priv, p_ranked: ranked, p_voice: voice, p_settings: { ...ruleToSettings(rule), field, turn, ball: 0 } })} />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  tile: { flex: 1, height: 76, borderRadius: 18, borderWidth: 1, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  go: { width: 64, height: 44, borderRadius: 14, marginRight: S.s, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(79,227,255,.18)', borderWidth: 1, borderColor: C.cyan },
  lbl: { fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginTop: S.l, marginBottom: S.s },
  optRow: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 56, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,.1)' },
});
