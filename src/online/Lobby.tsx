// Room lobby: seats per team, spectators, ready / start, host settings + kick, chat, voice, share code.
import React, { memo, useEffect, useMemo, useRef, useState } from 'react';
import { ScrollView, Share, StyleSheet, View } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { FIELD_THUMB, UI2 } from '../game/assets';
import { FIELDS } from '../game/data';
import { Btn, Img, Panel, Press, Segment, T } from '../ui/kit';
import { Sheet, SheetHandle } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { RoomPlayer, errFa, rpc, teamSize } from '../net/supabase';
import { RoomLink, useLink } from './link';
import { Avatar, Badge, ChatPanel, Field, Header, S, PingBadge, Spinner, StatBars, TS, VoiceBar, useVoice } from './ui';
import { discStats } from '../net/discs';
import { ruleLabel } from './OnlineMatch';

type Props = { link: RoomLink; onLeave: () => void; onWatch: () => void; toast: (m: string, k?: string) => void };

export default function Lobby(props: Props) {
  const st = useLink(props.link);
  if (!st.room) return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner size={36} /></View>;
  return <LobbyBody {...props} />;
}

function LobbyBody({ link, onLeave, onWatch, toast }: Props) {
  const ins = useSafeAreaInsets();
  const st = useLink(link); const v = useVoice(link);
  const room = st.room!; const me = link.me;
  const [busy, setBusy] = useState<string | null>(null);
  const [sheet, setSheet] = useState<null | 'chat' | 'settings'>(null);
  const sheetRef = useRef<SheetHandle>(null);

  const n = room ? teamSize(room.mode) : 1;
  const seats = useMemo(() => {
    const t: (RoomPlayer | null)[][] = [Array(n).fill(null), Array(n).fill(null)];
    for (const p of st.players) if (p.role === 'player' && (p.team === 0 || p.team === 1) && p.slot !== null && p.slot < n) t[p.team][p.slot] = p;
    return t;
  }, [st.players, n]);
  const specs = st.players.filter(p => p.role === 'spectator');
  const meP = st.players.find(p => p.user_id === me);
  const isHost = room.host === me;
  const amPlayer = meP?.role === 'player';
  const full = seats[0].every(Boolean) && seats[1].every(Boolean);
  const notReady = st.players.filter(p => p.role === 'player' && !p.ready && p.user_id !== room.host);
  const canStart = isHost && full && notReady.length === 0 && room.status === 'waiting';
  const speaking = new Set(v.speaking);

  const run = async (key: string, fn: () => Promise<any>, ok?: string) => {
    if (busy) return; setBusy(key);
    try { await fn(); link.ping(); await link.refresh(); if (ok) toast(ok, 'ok'); }
    catch (e) { toast(errFa(e), 'err'); buzz('heavy'); }
    finally { setBusy(null); }
  };

  const sit = (team: 0 | 1, slot: number) => run(`seat${team}${slot}`, () => rpc('take_seat', { p_room: room.id, p_team: team, p_slot: slot }));
  const ready = () => run('ready', async () => { await rpc('set_ready', { p_room: room.id, p_ready: !meP?.ready }); sfx('ready'); buzz('medium'); });
  const start = () => run('start', async () => { await rpc<string>('start_match', { p_room: room.id }); buzz('heavy'); });
  const kick = (uid: string) => run('kick' + uid, () => rpc('kick', { p_room: room.id, p_user: uid }), 'بازیکن اخراج شد');
  const watch = () => run('spec', () => rpc('spectate', { p_room: room.id }));
  const copy = async () => { try { await Clipboard.setStringAsync(room.code); toast('کد اتاق کپی شد', 'ok'); buzz('light'); } catch { toast('کپی ناموفق بود', 'err'); } };
  const share = () => { Share.share({ message: `بیا NEXORA بازی کنیم! 🚀\nکد اتاق: ${room.code}` }).catch(() => {}); };

  // quick / arena rooms: as soon as every seat is filled (players are auto-ready) the host starts after 3-2-1
  const auto = (room.kind === 'quick' || room.kind === 'arena') && room.status === 'waiting' && full && notReady.length === 0;
  const [count, setCount] = useState(0);
  const startRef = useRef(start); startRef.current = start;
  useEffect(() => {
    if (!auto) { setCount(0); return; }
    let n = 3; setCount(n); sfx('tick'); buzz('light');
    const id = setInterval(() => {
      n--; if (n > 0) { setCount(n); sfx('tick'); buzz('light'); return; }
      clearInterval(id); setCount(0); if (isHost) startRef.current();
    }, 1000);
    return () => clearInterval(id);
  }, [auto, isHost]);

  const reason = !full ? 'منتظر پر شدن جایگاه‌ها…' : notReady.length ? `منتظر آماده شدن ${fa(notReady.length)} بازیکن…` : '';
  const playing = room.status === 'playing';

  return (
    <View style={{ flex: 1 }}>
      <Header title={room.name} en={`LOBBY · ${room.mode.toUpperCase()}`} onBack={onLeave}
        right={<View style={{ flexDirection: 'row', alignItems: 'center' }}><Press onPress={share} style={s.hBtn}><Img src={UI2.c_mega} style={{ width: 24, height: 24 }} /></Press><View style={{ marginLeft: S.s }}><PingBadge link={link} /></View></View>} />
      <ScrollView contentContainerStyle={{ paddingTop: ins.top + 76, paddingBottom: 140 + ins.bottom, paddingHorizontal: S.l }} showsVerticalScrollIndicator={false}>
        {/* info strip */}
        <Panel style={{ padding: S.m }} accent={C.cyan}>
          <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
            <View style={{ flex: 1, alignItems: 'flex-end' }}>
              <T s="کد اتاق" style={{ fontSize: TS.cap, color: C.dim }} />
              <T s={room.code} style={{ fontFamily: F.title, fontSize: 24, letterSpacing: 4, color: C.cyan }} />
            </View>
            <Press onPress={copy} style={s.codeBtn}><T s="کپی" style={{ fontFamily: F.bold, fontSize: TS.small }} /></Press>
            <Press onPress={share} style={[s.codeBtn, { marginRight: S.s }]}><T s="اشتراک" style={{ fontFamily: F.bold, fontSize: TS.small }} /></Press>
          </View>
          <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', marginTop: S.s, rowGap: S.xs }}>
            <Badge label={ruleLabel(room.settings)} color={C.violet} />
            <Badge label={FIELDS[room.settings?.field ?? 0]?.name || 'Field'} color={C.sky} />
            <Badge label={room.ranked ? 'رتبه‌ای' : 'دوستانه'} color={room.ranked ? C.gold : C.green} />
            {room.is_private ? <Badge label="خصوصی" color={C.pink} /> : null}
            {room.tournament_match_id ? <Badge label="تورنمنت" color={C.orange} /> : null}
            {playing ? <Badge label="در حال بازی" color={C.red} live /> : null}
          </View>
        </Panel>

        {/* teams */}
        <View style={{ flexDirection: 'row-reverse', marginTop: S.m }}>
          {[0, 1].map(t => (
            <View key={t} style={{ flex: 1, marginLeft: t === 0 ? S.s : 0 }}>
              <View style={[s.teamHead, { borderColor: (t === 0 ? C.cyan : C.red) + '66' }]}>
                <LinearGradient colors={[(t === 0 ? C.cyan : C.red) + '30', 'transparent']} style={StyleSheet.absoluteFill} />
                <T s={t === 0 ? 'تیم آبی' : 'تیم قرمز'} style={{ fontFamily: F.bold, fontSize: TS.body, color: t === 0 ? C.cyan : C.red }} />
              </View>
              {seats[t].map((p, i) => p
                ? <Seat key={p.user_id} p={p} me={me} host={room.host} online={!!st.online[p.user_id]} talking={speaking.has(p.user_id)} color={t === 0 ? C.cyan : C.red}
                  canKick={isHost && p.user_id !== me && !playing} onKick={() => kick(p.user_id)} busy={busy === 'kick' + p.user_id} />
                : <Press key={i} onPress={() => sit(t as 0 | 1, i)} disabled={playing || !!busy} style={s.empty}>
                  {busy === `seat${t}${i}` ? <Spinner /> : <><T s="+" style={{ fontFamily: F.title, fontSize: 18, color: C.dim }} /><T s="نشستن" style={{ fontSize: TS.cap, color: C.dim, marginRight: S.xs }} /></>}
                </Press>)}
            </View>
          ))}
        </View>

        {/* spectators */}
        <Panel style={{ padding: S.m, marginTop: S.m }} accent="transparent">
          <View style={{ flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }}>
            <T s={`تماشاگرها (${fa(specs.length)})`} style={{ fontFamily: F.bold, fontSize: TS.small }} />
            {amPlayer && !playing ? <Press onPress={watch} style={s.smallBtn}><T s="فقط تماشا" style={{ fontSize: TS.cap, color: C.sky }} /></Press> : null}
          </View>
          {specs.length ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: S.s }} contentContainerStyle={{ flexDirection: 'row-reverse' }}>
              {specs.map(p => (
                <View key={p.user_id} style={{ alignItems: 'center', width: 64, marginLeft: S.s }}>
                  <Avatar avatar={p.profiles?.equipped_disc || p.profiles?.avatar} url={p.profiles?.avatar_url} size={40} ring={speaking.has(p.user_id) ? C.green : C.dim2} dim={!st.online[p.user_id]} />
                  <T s={p.profiles?.username || '…'} n={1} style={{ fontSize: TS.tiny, color: C.dim, marginTop: 2, maxWidth: 62 }} />
                </View>
              ))}
            </ScrollView>
          ) : <T s="کسی تماشا نمی‌کند" style={{ fontSize: TS.cap, color: C.dim2, textAlign: 'right', marginTop: S.xs }} />}
        </Panel>

        {/* voice */}
        <Panel style={{ padding: S.m, marginTop: S.m }} accent="transparent">
          <T s="چت صوتی" style={{ fontFamily: F.bold, fontSize: TS.small, textAlign: 'right', marginBottom: S.s }} />
          <VoiceBar link={link} enabled={room.voice} />
        </Panel>

        {/* chat preview */}
        <Press onPress={() => setSheet('chat')} scaleTo={.98} style={{ marginTop: S.m }}>
          <Panel style={{ padding: S.m, flexDirection: 'row-reverse', alignItems: 'center' }} accent="transparent">
            <Img src={UI2.c_bell} style={{ width: 32, height: 32 }} />
            <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
              <T s="گفتگوی اتاق" style={{ fontFamily: F.bold, fontSize: TS.small }} />
              <T s={st.chat.length ? `${st.chat[st.chat.length - 1].name}: ${st.chat[st.chat.length - 1].text}` : 'برای نوشتن پیام لمس کن'} n={1} style={{ fontSize: TS.cap, color: C.dim, marginTop: 2 }} />
            </View>
            {st.unread ? <View style={s.unread}><T s={fa(Math.min(99, st.unread))} style={{ fontFamily: F.bold, fontSize: 10, color: '#fff' }} /></View> : null}
          </Panel>
        </Press>

        {isHost && !playing && !room.tournament_match_id ? (
          <Btn label="تنظیمات اتاق" small colors={G.dark} onPress={() => setSheet('settings')} style={{ marginTop: S.m }} />
        ) : null}
      </ScrollView>

      {/* action bar */}
      <View style={[s.bar, { paddingBottom: Math.max(ins.bottom, S.m) }]}>
        <LinearGradient pointerEvents="none" colors={['transparent', 'rgba(2,4,14,.92)', 'rgba(2,4,14,.98)']} style={StyleSheet.absoluteFill} />
        {playing ? (
          <Btn label="ورود به بازی زنده" onPress={onWatch} colors={G.red} />
        ) : (room.kind === 'quick' || room.kind === 'arena') ? (
          <T s={full ? 'آماده‌ی شروع…' : `در جستجوی حریف… (${fa(st.players.filter(p => p.role === 'player').length)}/${fa(n * 2)})`} style={{ fontFamily: F.bold, fontSize: TS.body, color: C.cyan, textAlign: 'center', paddingVertical: S.m }} />
        ) : isHost ? (
          <>
            {reason ? <T s={reason} style={{ fontSize: TS.cap, color: C.dim, textAlign: 'center', marginBottom: S.s }} /> : null}
            <Btn label={busy === 'start' ? 'در حال شروع…' : 'شروع بازی'} onPress={start} disabled={!canStart || !!busy} colors={canStart ? G.gold : G.dark} />
          </>
        ) : amPlayer ? (
          <Btn label={meP?.ready ? 'آماده‌ام ✓' : 'اعلام آمادگی'} onPress={ready} disabled={!!busy} colors={meP?.ready ? G.green : G.primary} />
        ) : (
          <T s="برای بازی روی یک جایگاه خالی بزن" style={{ fontSize: TS.small, color: C.dim, textAlign: 'center', paddingVertical: S.m }} />
        )}
      </View>

      {count > 0 ? (
        <View style={s.count} pointerEvents="none">
          <T s={fa(count)} style={{ fontFamily: F.title, fontSize: 96, color: '#fff', textShadowColor: C.cyan, textShadowRadius: 30 }} />
          <T s="بازی شروع می‌شود" style={{ fontFamily: F.bold, fontSize: TS.h, color: C.cyan }} />
        </View>
      ) : null}

      {sheet ? (
        <Sheet ref={sheetRef} onClosed={() => setSheet(null)} title={sheet === 'chat' ? 'گفتگو' : 'تنظیمات اتاق'} en={sheet === 'chat' ? 'ROOM CHAT' : 'ROOM SETTINGS'} height={sheet === 'chat' ? .72 : .8}>
          {sheet === 'chat' ? <ChatPanel link={link} /> : <RoomSettings link={link} toast={toast} onDone={() => sheetRef.current?.close()} />}
        </Sheet>
      ) : null}
    </View>
  );
}

const Seat = memo(function Seat({ p, me, host, online, talking, color, canKick, onKick, busy }: { p: RoomPlayer; me: string; host: string; online: boolean; talking: boolean; color: string; canKick: boolean; onKick: () => void; busy: boolean }) {
  const isHost = p.user_id === host;
  return (
    <View style={[s.seat, { borderColor: talking ? C.green : p.user_id === me ? color : C.line }]}>
      <View>
        <Avatar avatar={p.profiles?.equipped_disc || p.profiles?.avatar} url={p.profiles?.avatar_url} size={40} ring={talking ? C.green : color} dim={!online} />
        <View style={[s.dotOn, { backgroundColor: online ? C.green : C.dim2 }]} />
      </View>
      <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
        <T s={(isHost ? '👑 ' : '') + (p.profiles?.username || '…')} n={1} style={{ fontFamily: F.bold, fontSize: TS.small }} />
        <T s={isHost ? 'میزبان' : p.ready ? 'آماده ✓' : 'آماده نیست'} n={1} style={{ fontSize: TS.tiny, color: isHost ? C.gold : p.ready ? C.green : C.dim2 }} />
        <StatBars {...discStats(p.disc_id || p.profiles?.equipped_disc)} compact />
      </View>
      {canKick ? <Press onPress={onKick} style={s.kick} disabled={busy}><T s="✕" style={{ fontSize: 12, color: C.red }} /></Press> : null}
    </View>
  );
});

const RULES: [string, string][] = [['g3', 'تا ۳ گل'], ['g5', 'تا ۵ گل'], ['t3', '۳ دقیقه'], ['t5', '۵ دقیقه']];
export const ruleToSettings = (r: string) => (r === 'g3' ? { goals: 3, time: 0 } : r === 'g5' ? { goals: 5, time: 0 } : r === 't5' ? { goals: 3, time: 300 } : { goals: 3, time: 180 });
export const settingsToRule = (st: any) => (Number(st?.time) >= 300 ? 't5' : Number(st?.time) > 0 ? 't3' : Number(st?.goals) >= 5 ? 'g5' : 'g3');

export function FieldPicker({ value, onChange }: { value: number; onChange: (i: number) => void }) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingVertical: S.xs }}>
      {FIELDS.map((f, i) => (
        <Press key={f.id} onPress={() => onChange(i)} style={[s.field, i === value && { borderColor: C.cyan, backgroundColor: 'rgba(79,227,255,.12)' }]}>
          <Img src={FIELD_THUMB[f.id]} style={{ width: 44, height: 58, borderRadius: 6 }} fit="cover" />
          <T s={f.name} n={1} style={{ fontSize: TS.tiny, color: i === value ? C.text : C.dim, marginTop: 2, maxWidth: 70 }} />
        </Press>
      ))}
    </ScrollView>
  );
}

function RoomSettings({ link, toast, onDone }: { link: RoomLink; toast: (m: string, k?: string) => void; onDone: () => void }) {
  const room = link.state.room!;
  const [name, setName] = useState(room.name);
  const [rule, setRule] = useState(settingsToRule(room.settings));
  const [turn, setTurn] = useState<number>(room.settings?.turn ?? 15);
  const [field, setField] = useState<number>(room.settings?.field ?? 0);
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    try {
      await rpc('update_room', { p_room: room.id, p_settings: { ...room.settings, ...ruleToSettings(rule), turn, field }, p_name: name.trim().slice(0, 40) });
      link.ping(); await link.refresh(); toast('تنظیمات ذخیره شد', 'ok'); onDone();
    } catch (e) { toast(errFa(e), 'err'); } finally { setBusy(false); }
  };
  return (
    <ScrollView contentContainerStyle={{ padding: S.l, paddingBottom: S.xl }} keyboardShouldPersistTaps="handled">
      <Field label="نام اتاق" value={name} onChangeText={setName} maxLength={40} />
      <T s="قانون بازی" style={s.lbl} />
      <Segment value={rule} onChange={setRule} items={RULES} accent={C.violet} />
      <T s="زمان هر نوبت" style={s.lbl} />
      <Segment value={turn} onChange={setTurn} items={[[10, '۱۰ث'], [15, '۱۵ث'], [20, '۲۰ث'], [0, 'بدون']]} accent={C.green} />
      <T s="زمین" style={s.lbl} />
      <FieldPicker value={field} onChange={setField} />
      <Btn label={busy ? 'در حال ذخیره…' : 'ذخیره'} onPress={save} disabled={busy} style={{ marginTop: S.l }} />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  hBtn: { width: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,14,40,.85)', borderWidth: 1, borderColor: C.line },
  codeBtn: { minWidth: 64, height: 44, paddingHorizontal: S.m, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(79,227,255,.12)', borderWidth: 1, borderColor: C.cyan + '88' },
  teamHead: { height: 36, borderRadius: 12, borderWidth: 1, alignItems: 'center', justifyContent: 'center', overflow: 'hidden', marginBottom: S.s },
  seat: { minHeight: 68, paddingVertical: 6, flexDirection: 'row-reverse', alignItems: 'center', paddingHorizontal: S.s, borderRadius: 16, borderWidth: 1, backgroundColor: 'rgba(10,16,44,.88)', marginBottom: S.s },
  empty: { height: 68, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'center', borderRadius: 16, borderWidth: 1, borderStyle: 'dashed', borderColor: C.dim2, marginBottom: S.s, backgroundColor: 'rgba(6,10,30,.4)' },
  dotOn: { position: 'absolute', bottom: 0, left: 0, width: 12, height: 12, borderRadius: 6, borderWidth: 2, borderColor: '#0b1236' },
  kick: { width: 40, height: 44, alignItems: 'center', justifyContent: 'center' },
  smallBtn: { height: 36, paddingHorizontal: S.m, borderRadius: 12, borderWidth: 1, borderColor: C.sky + '66', justifyContent: 'center' },
  unread: { minWidth: 22, height: 22, paddingHorizontal: 4, borderRadius: 11, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center' },
  count: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(2,4,14,.7)', alignItems: 'center', justifyContent: 'center', zIndex: 50 },
  bar: { position: 'absolute', left: 0, right: 0, bottom: 0, paddingHorizontal: S.l, paddingTop: S.xl },
  field: { width: 78, alignItems: 'center', padding: S.xs, marginLeft: S.s, borderRadius: 12, borderWidth: 1, borderColor: C.line },
  lbl: { fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginTop: S.l, marginBottom: S.s },
});
