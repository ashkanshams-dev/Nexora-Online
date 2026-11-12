// Tournaments: list (registration / running / finished), create, detail with bracket or standings, live updates.
import React, { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI2 } from '../game/assets';
import { Btn, Img, Panel, Press, Segment, T } from '../ui/kit';
import { Sheet, SheetHandle } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { Entry, Format, Mode, Room, TMatch, Tournament, errFa, rpc, supabase } from '../net/supabase';
import { useOracle } from '../oracle/Oracle';
import { Badge, Card, Empty, ErrorState, Field, Header, S, Skeleton, Spinner, TS, Tabs } from './ui';

export const FORMAT_FA: Record<Format, string> = { single_elim: 'حذفی تک', double_elim: 'حذفی دوگانه', round_robin: 'دوره‌ای', swiss: 'سوئیسی', league: 'لیگ' };
const STATUS_FA: Record<Tournament['status'], [string, string]> = { registration: ['ثبت‌نام', C.green], running: ['در جریان', C.orange], finished: ['پایان‌یافته', C.dim] };
const isElim = (f: Format) => f === 'single_elim' || f === 'double_elim';

type ListProps = { onBack: () => void; onOpen: (id: string) => void; toast: (m: string, k?: string) => void };

export default function Tournaments({ onBack, onOpen, toast }: ListProps) {
  const ins = useSafeAreaInsets();
  const [tab, setTab] = useState<Tournament['status']>('registration');
  const [rows, setRows] = useState<(Tournament & { entries: { count: number }[] })[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [sheet, setSheet] = useState(false);
  const sheetRef = useRef<SheetHandle>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from('tournaments').select('*, entries:tournament_entries(count)').eq('status', tab).order('created_at', { ascending: false }).limit(50);
    if (error) { setErr(errFa(error)); return; }
    setErr(null); setRows(data as any);
  }, [tab]);
  useEffect(() => {
    setRows(null); load();
    let t: ReturnType<typeof setTimeout> | null = null;
    const soon = () => { if (t) clearTimeout(t); t = setTimeout(load, 500); };
    const ch = supabase.channel(`tours:${tab}`).on('postgres_changes', { event: '*', schema: 'public', table: 'tournaments' }, soon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tournament_entries' }, soon).subscribe();
    return () => { if (t) clearTimeout(t); supabase.removeChannel(ch); };
  }, [load, tab]);

  return (
    <View style={{ flex: 1 }}>
      <Header title="تورنمنت‌ها" en="TOURNAMENTS" accent={C.orange} onBack={onBack}
        right={<Press onPress={() => setSheet(true)} style={st.add}><T s="+" style={{ fontFamily: F.title, fontSize: 22, color: C.green }} /></Press>} />
      <FlatList
        data={rows || []} keyExtractor={r => r.id}
        ListHeaderComponent={<View style={{ paddingHorizontal: S.l, marginBottom: S.m }}><Tabs items={[['registration', 'ثبت‌نام'], ['running', 'در جریان'], ['finished', 'تمام‌شده']]} value={tab} onChange={setTab} /></View>}
        renderItem={({ item }) => <TourRow t={item} count={item.entries?.[0]?.count ?? 0} onPress={() => onOpen(item.id)} />}
        ListEmptyComponent={err ? <ErrorState msg={err} onRetry={load} /> : !rows ? <Skeleton rows={4} h={92} /> :
          <Empty img={UI2.x_trophy} title="تورنمنتی در این بخش نیست" sub={tab === 'registration' ? 'اولین تورنمنت را خودت بساز!' : undefined} action={tab === 'registration' ? 'ساخت تورنمنت' : undefined} onAction={() => setSheet(true)} />}
        contentContainerStyle={{ paddingTop: ins.top + 76, paddingBottom: ins.bottom + S.xl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} tintColor={C.cyan} progressViewOffset={ins.top + 70} />}
        showsVerticalScrollIndicator={false} />
      {sheet ? (
        <Sheet ref={sheetRef} onClosed={() => setSheet(false)} title="ساخت تورنمنت" en="NEW TOURNAMENT" accent={C.orange} height={.9}>
          <CreateTournament toast={toast} onDone={id => { sheetRef.current?.close(); onOpen(id); }} />
        </Sheet>
      ) : null}
    </View>
  );
}

const TourRow = memo(function TourRow({ t, count, onPress }: { t: Tournament; count: number; onPress: () => void }) {
  const [sl, sc] = STATUS_FA[t.status];
  return (
    <View style={{ paddingHorizontal: S.l, marginBottom: S.s }}>
      <Card onPress={onPress} accent={sc}>
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
          <Img src={t.status === 'finished' ? UI2.x_medal : UI2.x_trophy} style={{ width: 52, height: 52 }} />
          <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
            <T s={t.name} n={1} style={{ fontFamily: F.bold, fontSize: TS.body }} />
            <View style={{ flexDirection: 'row-reverse', marginTop: S.xs, flexWrap: 'wrap', rowGap: 4 }}>
              <Badge label={FORMAT_FA[t.format]} color={C.violet} /><Badge label={t.mode.toUpperCase()} color={C.sky} /><Badge label={sl} color={sc} live={t.status === 'running'} />
            </View>
          </View>
          <View style={{ alignItems: 'center', minWidth: 60 }}>
            <T s={`${fa(count)}/${fa(t.max_entries)}`} style={{ fontFamily: F.title, fontSize: TS.h }} />
            <T s={`💎 ${fa(t.prize_gems ?? 0)}`} style={{ fontSize: TS.cap, color: '#9fd8ff', marginTop: 2 }} />
          </View>
        </View>
      </Card>
    </View>
  );
});

function CreateTournament({ toast, onDone }: { toast: (m: string, k?: string) => void; onDone: (id: string) => void }) {
  const [name, setName] = useState('');
  const [format, setFormat] = useState<Format>('single_elim');
  const [mode, setMode] = useState<Mode>('1v1');
  const [max, setMax] = useState(8);
  const [rounds, setRounds] = useState(2);
  const [gems, setGems] = useState(20);
  const [minLv, setMinLv] = useState(1);
  const [busy, setBusy] = useState(false);
  const go = async () => {
    if (name.trim().length < 3) { toast('نام تورنمنت حداقل ۳ کاراکتر', 'err'); return; }
    setBusy(true);
    try {
      const t = await rpc<Tournament>('create_tournament', { p_name: name.trim(), p_format: format, p_mode: mode, p_max: max, p_rounds: format === 'league' || format === 'swiss' ? rounds : null, p_prize_gems: gems, p_starts: null, p_min_level: minLv });
      sfx('ready'); buzz('success'); toast('تورنمنت ساخته شد', 'ok'); onDone(t.id);
    } catch (e) { toast(errFa(e), 'err'); } finally { setBusy(false); }
  };
  return (
    <ScrollView contentContainerStyle={{ padding: S.l, paddingBottom: S.xl * 2 }} keyboardShouldPersistTaps="handled">
      <Field label="نام تورنمنت" value={name} onChangeText={setName} maxLength={40} placeholder="جام کهکشان" />
      <T s="فرمت" style={st.lbl} />
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', gap: S.s }}>
        {(Object.keys(FORMAT_FA) as Format[]).map(f => (
          <Press key={f} onPress={() => setFormat(f)} style={[st.chip, f === format && st.chipOn]}><T s={FORMAT_FA[f]} style={{ fontFamily: F.bold, fontSize: TS.small, color: f === format ? '#fff' : C.dim }} /></Press>
        ))}
      </View>
      <T s="حالت" style={st.lbl} />
      <Segment value={mode} onChange={setMode} items={[['1v1', '1v1'], ['2v2', '2v2'], ['3v3', '3v3']]} />
      <T s="ظرفیت" style={st.lbl} />
      <Segment value={max} onChange={setMax} items={[[4, '۴'], [8, '۸'], [16, '۱۶'], [32, '۳۲'], [64, '۶۴']]} accent={C.orange} />
      {format === 'league' || format === 'swiss' ? (<>
        <T s={format === 'league' ? 'تعداد دور رفت و برگشت' : 'تعداد دورها'} style={st.lbl} />
        <Segment value={rounds} onChange={setRounds} items={format === 'league' ? [[1, 'یک'], [2, 'دو'], [3, 'سه']] : [[3, '۳'], [4, '۴'], [5, '۵'], [6, '۶']]} accent={C.violet} />
      </>) : null}
      <T s="جایزه‌ی قهرمان (الماس) — نایب‌قهرمان یک‌سوم" style={st.lbl} />
      <Segment value={gems} onChange={setGems} items={[[0, '۰'], [10, '۱۰'], [20, '۲۰'], [30, '۳۰']]} accent={C.sky} />
      <T s="حداقل سطح" style={st.lbl} />
      <Segment value={minLv} onChange={setMinLv} items={[[1, '۱'], [3, '۳'], [5, '۵'], [10, '۱۰']]} accent={C.green} />
      <Btn label={busy ? 'در حال ساخت…' : 'ساخت تورنمنت'} onPress={go} disabled={busy} colors={G.gold} style={{ marginTop: S.l }} />
    </ScrollView>
  );
}

// ======================= detail =======================
type DetailProps = { id: string; onBack: () => void; onRoom: (r: Room) => void; toast: (m: string, k?: string) => void };

export function TournamentDetail({ id, onBack, onRoom, toast }: DetailProps) {
  const ins = useSafeAreaInsets(); const { uid } = useAuth();
  const [t, setT] = useState<Tournament | null>(null);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [matches, setMatches] = useState<TMatch[]>([]);
  const [names, setNames] = useState<Record<string, string>>({});
  const [err, setErr] = useState<string | null>(null);
  const [tab, setTab] = useState<'board' | 'entries'>('board');
  const [busy, setBusy] = useState<string | null>(null);
  const [teamName, setTeamName] = useState('');
  const [ovr, setOvr] = useState<TMatch | null>(null);

  const load = useCallback(async () => {
    const [a, b, c] = await Promise.all([
      supabase.from('tournaments').select('*').eq('id', id).maybeSingle(),
      supabase.from('standings').select('*').eq('tournament_id', id).order('pos'),
      supabase.from('tournament_matches').select('*').eq('tournament_id', id).order('round').order('idx'),
    ]);
    if (a.error || b.error || c.error) { setErr(errFa(a.error || b.error || c.error)); return; }
    setErr(null); setT(a.data as Tournament); setEntries((b.data || []) as Entry[]); setMatches((c.data || []) as TMatch[]);
    const nm: Record<string, string> = {}; for (const e of (b.data || []) as Entry[]) nm[e.id] = e.team_name; setNames(nm);
  }, [id]);
  useEffect(() => {
    load();
    let tm: ReturnType<typeof setTimeout> | null = null;
    const soon = () => { if (tm) clearTimeout(tm); tm = setTimeout(load, 300); };
    const ch = supabase.channel(`tour:${id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tournaments', filter: `id=eq.${id}` }, soon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tournament_entries', filter: `tournament_id=eq.${id}` }, soon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tournament_matches', filter: `tournament_id=eq.${id}` }, soon)
      .subscribe();
    return () => { if (tm) clearTimeout(tm); supabase.removeChannel(ch); };
  }, [id, load]);

  const myEntry = entries.find(e => uid && e.members?.includes(uid));
  const isOrg = !!t && t.created_by === uid;
  const next = myEntry ? matches.find(m => (m.status === 'ready' || m.status === 'live') && (m.entry_a === myEntry.id || m.entry_b === myEntry.id)) : undefined;
  const run = async (k: string, fn: () => Promise<any>, ok?: string) => {
    if (busy) return; setBusy(k);
    try { await fn(); if (ok) { toast(ok, 'ok'); buzz('success'); } await load(); } catch (e) { toast(errFa(e), 'err'); buzz('heavy'); } finally { setBusy(null); }
  };
  const oracle = useOracle();
  useEffect(() => { if (next && next.status === 'ready') oracle.react('tourReady'); }, [next?.id, next?.status]);
  const openRoom = (tm: TMatch) => run('room', async () => { const r = await rpc<Room>('open_tournament_room', { p_tm: tm.id }); onRoom(r); });

  if (err && !t) return <View style={{ flex: 1 }}><Header title="تورنمنت" onBack={onBack} /><View style={{ paddingTop: ins.top + 90 }}><ErrorState msg={err} onRetry={load} /></View></View>;
  if (!t) return <View style={{ flex: 1 }}><Header title="تورنمنت" onBack={onBack} /><View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner size={36} /></View></View>;
  const [sl, sc] = STATUS_FA[t.status];
  const winner = t.winner_entry ? names[t.winner_entry] : null;

  return (
    <View style={{ flex: 1 }}>
      <Header title={t.name} en={`${FORMAT_FA[t.format]} · ${t.mode.toUpperCase()}`} accent={C.orange} onBack={onBack} />
      <ScrollView contentContainerStyle={{ paddingTop: ins.top + 76, paddingBottom: ins.bottom + S.xl }} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        <View style={{ paddingHorizontal: S.l }}>
          <Panel style={{ padding: S.m }} accent={sc}>
            <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', rowGap: 4 }}>
              <Badge label={sl} color={sc} live={t.status === 'running'} /><Badge label={`${fa(entries.length)}/${fa(t.max_entries)} شرکت‌کننده`} color={C.sky} />
              <Badge label={`💎 ${fa(t.prize_gems ?? 0)} قهرمان`} color="#9fd8ff" /><Badge label={`${fa(t.prize_xp)} XP`} color={C.cyan} />
              {t.min_level > 1 ? <Badge label={`حداقل سطح ${fa(t.min_level)}`} color={C.green} /> : null}
              {t.status !== 'registration' && t.current_round ? <Badge label={`دور ${fa(t.current_round)}`} color={C.violet} /> : null}
            </View>
            {winner ? (
              <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginTop: S.m }}>
                <Img src={UI2.x_trophy} style={{ width: 44, height: 44 }} />
                <T s={`قهرمان: ${winner}`} style={{ fontFamily: F.title, fontSize: TS.h, color: C.gold, marginRight: S.s }} />
              </View>
            ) : null}
          </Panel>

          {/* actions */}
          {t.status === 'registration' ? (
            myEntry ? (
              <Btn label={busy === 'leave' ? '…' : 'انصراف از تورنمنت'} small colors={G.dark} style={{ marginTop: S.m }} onPress={() => run('leave', () => rpc('leave_tournament', { p_tid: t.id }), 'از تورنمنت خارج شدی')} />
            ) : entries.length < t.max_entries ? (
              <View style={{ marginTop: S.m }}>
                {t.mode !== '1v1' ? <Field label="نام تیم (اختیاری)" value={teamName} onChangeText={setTeamName} maxLength={24} /> : null}
                <Btn label={busy === 'join' ? '…' : 'ثبت‌نام'} colors={G.green} onPress={() => run('join', () => rpc('join_tournament', { p_tid: t.id, p_team_name: teamName.trim() || null, p_members: null }), 'ثبت‌نام شدی!')} />
              </View>
            ) : <T s="ظرفیت تکمیل است" style={{ color: C.orange, textAlign: 'center', marginTop: S.m }} />
          ) : null}
          {isOrg && t.status === 'registration' ? (
            <Btn label={busy === 'start' ? '…' : `شروع تورنمنت (${fa(entries.length)} نفر)`} colors={G.gold} style={{ marginTop: S.s }} disabled={entries.length < 2}
              onPress={() => run('start', () => rpc('start_tournament', { p_tid: t.id }), 'تورنمنت شروع شد')} />
          ) : null}
          {next ? (
            <Panel style={{ padding: S.m, marginTop: S.m }} accent={C.red} glow>
              <T s="مسابقه‌ی بعدی تو" style={{ fontFamily: F.bold, fontSize: TS.small, color: C.red, textAlign: 'right' }} />
              <T s={`${names[next.entry_a || ''] || '؟'}  vs  ${names[next.entry_b || ''] || '؟'}`} n={1} style={{ fontFamily: F.title, fontSize: TS.h, textAlign: 'center', marginVertical: S.s }} />
              <Btn label={busy === 'room' ? '…' : 'ورود به مسابقه'} colors={G.red} onPress={() => openRoom(next)} />
            </Panel>
          ) : null}

          <View style={{ marginTop: S.l }}>
            <Tabs items={[['board', isElim(t.format) ? 'براکت' : 'جدول'], ['entries', 'شرکت‌کنندگان']]} value={tab} onChange={setTab} />
          </View>
        </View>

        <View style={{ marginTop: S.m }}>
          {tab === 'entries' ? (
            entries.length ? entries.map(e => (
              <View key={e.id} style={[st.row, { marginHorizontal: S.l }]}>
                <T s={e.seed ? `#${fa(e.seed)}` : '•'} style={{ width: 36, fontFamily: F.bold, color: C.dim, textAlign: 'right' }} />
                <T s={e.team_name} n={1} style={{ flex: 1, fontFamily: F.bold, fontSize: TS.body, textAlign: 'right', marginRight: S.s }} />
                {e.eliminated ? <Badge label="حذف" color={C.red} /> : e.final_rank === 1 ? <Badge label="قهرمان" color={C.gold} /> : null}
              </View>
            )) : <Empty title="هنوز کسی ثبت‌نام نکرده" />
          ) : t.status === 'registration' ? <Empty img={UI2.c_calendar} title="براکت بعد از شروع ساخته می‌شود" sub="برگزارکننده تورنمنت را شروع می‌کند" />
            : isElim(t.format) ? <Bracket matches={matches} names={names} format={t.format} myEntry={myEntry?.id} canOverride={isOrg} onOverride={setOvr} />
              : <Standings entries={entries} matches={matches} names={names} myEntry={myEntry?.id} canOverride={isOrg} onOverride={setOvr} />}
        </View>
      </ScrollView>
      {ovr ? <Override m={ovr} names={names} onClose={() => setOvr(null)} onSave={(a, b) => run('ovr', () => rpc('set_tournament_result', { p_tm: ovr.id, p_sa: a, p_sb: b }), 'نتیجه ثبت شد').then(() => setOvr(null))} /> : null}
    </View>
  );
}

// ---------- bracket (horizontally scrollable, round labels, connectors) ----------
export const roundLabel = (round: number, total: number) => {
  const left = total - round; // 0 = final
  return left === 0 ? 'فینال' : left === 1 ? 'نیمه‌نهایی' : left === 2 ? 'یک‌چهارم' : left === 3 ? 'یک‌هشتم' : left === 4 ? 'یک‌شانزدهم' : `دور ${fa(round)}`;
};
const BOX_W = 168, BOX_H = 64, GAP = 14, COL_GAP = 28;

function Bracket({ matches, names, format, myEntry, canOverride, onOverride }: { matches: TMatch[]; names: Record<string, string>; format: Format; myEntry?: string; canOverride: boolean; onOverride: (m: TMatch) => void }) {
  const sections: [string, TMatch[]][] = format === 'double_elim'
    ? [['جدول برندگان', matches.filter(m => m.bracket === 'winners')], ['جدول بازندگان', matches.filter(m => m.bracket === 'losers')], ['فینال بزرگ', matches.filter(m => m.bracket === 'final')]]
    : [['', matches.filter(m => m.bracket === 'main')]];
  return (
    <View>
      {sections.filter(([, ms]) => ms.length).map(([title, ms]) => <BracketSection key={title || 'main'} title={title} ms={ms} names={names} myEntry={myEntry} canOverride={canOverride} onOverride={onOverride} labels={format !== 'double_elim' || title === 'جدول برندگان'} />)}
    </View>
  );
}

function BracketSection({ title, ms, names, myEntry, canOverride, onOverride, labels }: { title: string; ms: TMatch[]; names: Record<string, string>; myEntry?: string; canOverride: boolean; onOverride: (m: TMatch) => void; labels: boolean }) {
  const rounds = useMemo(() => { const r: Record<number, TMatch[]> = {}; for (const m of ms) (r[m.round] ||= []).push(m); return Object.keys(r).map(Number).sort((a, b) => a - b).map(k => r[k].sort((a, b) => a.idx - b.idx)); }, [ms]);
  const total = rounds.length;
  const firstN = rounds[0]?.length || 1;
  const H = Math.max(firstN * (BOX_H + GAP), BOX_H + GAP);
  return (
    <View style={{ marginBottom: S.l }}>
      {title ? <T s={title} style={{ fontFamily: F.bold, fontSize: TS.body, textAlign: 'right', paddingHorizontal: S.l, marginBottom: S.s }} /> : null}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: S.l }}>
        <View style={{ flexDirection: 'row' }}>
          {rounds.map((col, ri) => {
            const slotH = H / col.length;
            return (
              <View key={ri} style={{ width: BOX_W + COL_GAP }}>
                <T s={labels ? roundLabel(ri + 1, total) : `دور ${fa(ri + 1)}`} style={{ fontFamily: F.bold, fontSize: TS.cap, color: C.cyan, textAlign: 'center', width: BOX_W, marginBottom: S.s }} />
                <View style={{ height: H }}>
                  {col.map((m, i) => {
                    const top = i * slotH + (slotH - BOX_H) / 2;
                    return (
                      <View key={m.id} style={{ position: 'absolute', top, left: 0 }}>
                        <MatchBox m={m} names={names} mine={!!myEntry && (m.entry_a === myEntry || m.entry_b === myEntry)} onPress={canOverride && (m.status === 'ready' || m.status === 'live') ? () => onOverride(m) : undefined} />
                        {ri < total - 1 ? (
                          <>
                            <View style={[st.lineH, { top: BOX_H / 2, left: BOX_W }]} />
                            <View style={[st.lineV, { left: BOX_W + COL_GAP / 2, top: i % 2 === 0 ? BOX_H / 2 : BOX_H / 2 - slotH / 2, height: slotH / 2 }]} />
                            {i % 2 === 0 ? <View style={[st.lineH, { top: BOX_H / 2 + slotH / 2, left: BOX_W + COL_GAP / 2 }]} /> : null}
                          </>
                        ) : null}
                      </View>
                    );
                  })}
                </View>
              </View>
            );
          })}
        </View>
      </ScrollView>
    </View>
  );
}

const MatchBox = memo(function MatchBox({ m, names, mine, onPress }: { m: TMatch; names: Record<string, string>; mine: boolean; onPress?: () => void }) {
  const live = m.status === 'live', done = m.status === 'done' || m.status === 'bye';
  const side = (e: string | null, sc: number | null) => {
    const win = !!e && m.winner_entry === e;
    return (
      <View style={[st.side, win && { backgroundColor: 'rgba(255,210,87,.14)' }]}>
        <T s={sc !== null && sc !== undefined ? fa(sc) : m.status === 'bye' && e ? '–' : ''} style={{ width: 22, fontFamily: F.title, fontSize: TS.small, color: win ? C.gold : C.dim, textAlign: 'center' }} />
        <T s={e ? names[e] || '…' : m.status === 'bye' ? 'استراحت' : '—'} n={1} style={{ flex: 1, fontSize: TS.small, color: e ? (win ? C.gold : C.text) : C.dim2, textAlign: 'right', fontFamily: win ? F.bold : F.body }} />
      </View>
    );
  };
  const body = (
    <View style={[st.box, mine && { borderColor: C.cyan }, live && { borderColor: C.red }, done && { opacity: .9 }]}>
      {side(m.entry_a, m.score_a)}
      <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: C.line }} />
      {side(m.entry_b, m.score_b)}
      {live ? <View style={st.liveDot} /> : null}
    </View>
  );
  return onPress ? <Press onPress={onPress} scaleTo={.97}>{body}</Press> : body;
});

function Standings({ entries, matches, names, myEntry, canOverride, onOverride }: { entries: Entry[]; matches: TMatch[]; names: Record<string, string>; myEntry?: string; canOverride: boolean; onOverride: (m: TMatch) => void }) {
  const open = matches.filter(m => m.status === 'ready' || m.status === 'live');
  return (
    <View style={{ paddingHorizontal: S.l }}>
      <View style={[st.tr, { borderBottomColor: C.lineHi }]}>
        {['#', 'تیم', 'بازی', 'ب', 'م', 'ش', 'گل', 'امتیاز'].map((h, i) => <T key={h} s={h} style={[st.td, i === 1 && { flex: 1, textAlign: 'right' }, { color: C.dim, fontFamily: F.bold }]} />)}
      </View>
      {entries.map(e => (
        <View key={e.id} style={[st.tr, e.id === myEntry && { backgroundColor: 'rgba(79,227,255,.1)' }]}>
          <T s={fa(e.pos ?? 0)} style={st.td} />
          <T s={e.team_name} n={1} style={[st.td, { flex: 1, textAlign: 'right', fontFamily: F.bold }]} />
          <T s={fa(e.played)} style={st.td} /><T s={fa(e.wins)} style={st.td} /><T s={fa(e.draws)} style={st.td} /><T s={fa(e.losses)} style={st.td} />
          <T s={`${fa(e.gf)}:${fa(e.ga)}`} style={[st.td, { width: 44 }]} />
          <T s={fa(e.points)} style={[st.td, { fontFamily: F.title, color: C.gold }]} />
        </View>
      ))}
      {open.length ? (
        <>
          <T s="مسابقات باز" style={{ fontFamily: F.bold, fontSize: TS.body, textAlign: 'right', marginTop: S.l, marginBottom: S.s }} />
          {open.map(m => (
            <Press key={m.id} onPress={canOverride ? () => onOverride(m) : undefined} disabled={!canOverride} scaleTo={.98}>
              <View style={[st.row, (m.entry_a === myEntry || m.entry_b === myEntry) && { borderColor: C.cyan }]}>
                <Badge label={`دور ${fa(m.round)}`} color={C.violet} />
                <T s={`${names[m.entry_a || ''] || '؟'}  vs  ${names[m.entry_b || ''] || '؟'}`} n={1} style={{ flex: 1, textAlign: 'right', fontSize: TS.small, marginRight: S.s }} />
                {m.status === 'live' ? <Badge label="زنده" color={C.red} live /> : null}
              </View>
            </Press>
          ))}
        </>
      ) : null}
    </View>
  );
}

function Override({ m, names, onClose, onSave }: { m: TMatch; names: Record<string, string>; onClose: () => void; onSave: (a: number, b: number) => void }) {
  const [a, setA] = useState(0), [b, setB] = useState(0);
  const step = (v: number, set: (n: number) => void) => (
    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
      <Press onPress={() => set(Math.max(0, v - 1))} style={st.step}><T s="−" style={{ fontSize: 20 }} /></Press>
      <T s={fa(v)} style={{ fontFamily: F.title, fontSize: 24, width: 40, textAlign: 'center' }} />
      <Press onPress={() => set(Math.min(30, v + 1))} style={st.step}><T s="+" style={{ fontSize: 20 }} /></Press>
    </View>
  );
  return (
    <View style={st.ovl}>
      <Panel style={{ width: '88%', maxWidth: 380, padding: S.l }} glow>
        <T s="ثبت نتیجه توسط برگزارکننده" style={{ fontFamily: F.bold, fontSize: TS.h, textAlign: 'center', marginBottom: S.m }} />
        {[[m.entry_a, a, setA], [m.entry_b, b, setB]].map(([e, v, set], i) => (
          <View key={i} style={{ flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', marginBottom: S.s }}>
            <T s={names[(e as string) || ''] || '؟'} n={1} style={{ flex: 1, fontSize: TS.body, textAlign: 'right' }} />
            {step(v as number, set as any)}
          </View>
        ))}
        <Btn label="ثبت" onPress={() => onSave(a, b)} colors={G.gold} style={{ marginTop: S.s }} />
        <Btn label="انصراف" small colors={G.dark} onPress={onClose} style={{ marginTop: S.s }} />
      </Panel>
    </View>
  );
}

const st = StyleSheet.create({
  add: { width: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(61,255,168,.12)', borderWidth: 1, borderColor: C.green + '88' },
  lbl: { fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginTop: S.l, marginBottom: S.s },
  chip: { height: 44, paddingHorizontal: S.l, borderRadius: 22, borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,12,34,.7)' },
  chipOn: { borderColor: C.violet, backgroundColor: C.violet + '33' },
  row: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 48, paddingHorizontal: S.m, marginBottom: S.s, borderRadius: 14, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(10,16,44,.85)' },
  box: { width: BOX_W, height: BOX_H, borderRadius: 12, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(10,16,44,.95)', overflow: 'hidden' },
  side: { flex: 1, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 6 },
  liveDot: { position: 'absolute', top: 4, left: 4, width: 7, height: 7, borderRadius: 4, backgroundColor: C.red },
  lineH: { position: 'absolute', width: COL_GAP / 2, height: 1.5, backgroundColor: 'rgba(120,200,255,.45)' },
  lineV: { position: 'absolute', width: 1.5, backgroundColor: 'rgba(120,200,255,.45)' },
  tr: { flexDirection: 'row-reverse', alignItems: 'center', height: 40, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: C.line, paddingHorizontal: 4 },
  td: { width: 30, fontSize: TS.small, textAlign: 'center' },
  step: { width: 44, height: 44, borderRadius: 14, borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,12,34,.8)' },
  ovl: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(2,4,14,.75)', alignItems: 'center', justifyContent: 'center', zIndex: 50 },
});
