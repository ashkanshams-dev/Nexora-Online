// Shared building blocks for the online screens (same space/neon kit as the rest of the app).
// Spacing follows an 8pt grid, touch targets are ≥ 44pt, Persian text is right-aligned / RTL.
import React, { memo, useEffect, useState } from 'react';
import { tr } from '../i18n';
import { ActivityIndicator, FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, TextInput, TextInputProps, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withRepeat, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TEAM_IMG, UI2 } from '../game/assets';
import { TEAMS, Team } from '../game/data';
import { teamKey } from '../game/util';
import { Btn, Img, Panel, Press, T } from '../ui/kit';
import { C, F, G, faNum } from '../ui/theme';
import type { League } from '../net/supabase';
import { supabase } from '../net/supabase';
import { RoomLink, useLink } from './link';
import type { VoiceState } from '../net/voice';
import { voiceSupport } from '../net/voice';
import { buzz } from '../sound';

export const S = { xs: 4, s: 8, m: 12, l: 16, xl: 24 };
export const TS = { title: 20, h: 16, body: 14, small: 12, cap: 11, tiny: 10 };

export const teamOfAvatar = (key?: string | null): Team => TEAMS.find(t => t.id === key || teamKey(t) === key) || TEAMS[0];
export const discImg = (key?: string | null) => TEAM_IMG[teamKey(teamOfAvatar(key))] || TEAM_IMG.club00;

export const Avatar = memo(function Avatar({ avatar, url, size = 40, ring = C.cyan, dim }: { avatar?: string | null; url?: string | null; size?: number; ring?: string; dim?: boolean }) {
  const src = url ? { uri: url } : discImg(avatar);
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, borderWidth: 2, borderColor: ring, backgroundColor: '#050816', alignItems: 'center', justifyContent: 'center', opacity: dim ? .5 : 1 }}>
      <Img src={src} fit={url ? 'cover' : 'contain'} style={{ width: size - 6, height: size - 6, borderRadius: (size - 6) / 2 }} />
    </View>
  );
});

// header with a 44pt back button; content is laid out below it
export function Header({ title, en, onBack, right, accent = C.cyan }: { title: string; en?: string; onBack: () => void; right?: React.ReactNode; accent?: string }) {
  const ins = useSafeAreaInsets();
  return (
    <View style={[st.header, { paddingTop: ins.top + S.s }]}>
      <LinearGradient pointerEvents="none" colors={['rgba(2,4,14,.95)', 'rgba(2,4,14,.7)', 'transparent']} style={StyleSheet.absoluteFill} />
      <Press onPress={onBack} style={st.back} haptic><T s="‹" style={{ fontFamily: F.title, fontSize: 26, color: C.text, marginTop: -4 }} /></Press>
      <View style={{ minWidth: 44, flexDirection: 'row', alignItems: 'center' }}>{right}</View>
      <View style={{ flex: 1, alignItems: 'flex-end', marginLeft: S.s }}>
        {en ? <T s={en} n={1} style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: accent }} /> : null}
        <T s={title} n={1} style={{ fontFamily: F.title, fontSize: TS.title }} />
      </View>
    </View>
  );
}

export function Spinner({ size = 28, color = C.cyan }: { size?: number; color?: string }) {
  return <ActivityIndicator size={size > 30 ? 'large' : 'small'} color={color} />;
}

// pulsing skeleton rows while lists load
export function Skeleton({ rows = 4, h = 72 }: { rows?: number; h?: number }) {
  const p = useSharedValue(0);
  useEffect(() => { p.value = withRepeat(withTiming(1, { duration: 900, easing: Easing.inOut(Easing.sin) }), -1, true); }, []);
  const a = useAnimatedStyle(() => ({ opacity: .35 + p.value * .35 }));
  return (
    <View style={{ paddingHorizontal: S.l }}>
      {Array.from({ length: rows }).map((_, i) => (
        <Animated.View key={i} style={[{ height: h, borderRadius: 18, marginBottom: S.s, backgroundColor: 'rgba(60,90,180,.18)', borderWidth: 1, borderColor: C.line }, a]} />
      ))}
    </View>
  );
}

export function Empty({ img = UI2.x_ball, title, sub, action, onAction }: { img?: any; title: string; sub?: string; action?: string; onAction?: () => void }) {
  return (
    <View style={{ alignItems: 'center', paddingVertical: S.xl, paddingHorizontal: S.xl }}>
      <Img src={img} style={{ width: 72, height: 72, opacity: .85 }} />
      <T s={title} style={{ fontFamily: F.bold, fontSize: TS.h, marginTop: S.s, textAlign: 'center' }} />
      {sub ? <T s={sub} style={{ fontSize: TS.small, color: C.dim, marginTop: S.xs, textAlign: 'center' }} /> : null}
      {action && onAction ? <Btn label={action} small onPress={onAction} colors={G.dark} style={{ marginTop: S.l, minWidth: 160 }} /> : null}
    </View>
  );
}

export function ErrorState({ msg, onRetry }: { msg: string; onRetry?: () => void }) {
  return <Empty img={UI2.c_bell} title="مشکلی پیش اومد" sub={msg} action={onRetry ? 'تلاش دوباره' : undefined} onAction={onRetry} />;
}

export function Badge({ label, color = C.cyan, live }: { label: string; color?: string; live?: boolean }) {
  const p = useSharedValue(0);
  useEffect(() => { if (live) p.value = withRepeat(withTiming(1, { duration: 700 }), -1, true); }, [live]);
  const a = useAnimatedStyle(() => ({ opacity: live ? .4 + p.value * .6 : 1 }));
  return (
    <View style={[st.badge, { borderColor: color + '88', backgroundColor: color + '22' }]}>
      {live ? <Animated.View style={[{ width: 6, height: 6, borderRadius: 3, backgroundColor: color, marginLeft: 4 }, a]} /> : null}
      <T s={label} n={1} style={{ fontFamily: F.bold, fontSize: TS.tiny, color }} />
    </View>
  );
}

export function Field(props: TextInputProps & { label?: string; error?: string | null }) {
  const { label, error, style, ...rest } = props;
  return (
    <View style={{ marginBottom: S.m }}>
      {label ? <T s={label} style={{ fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginBottom: S.xs }} /> : null}
      <TextInput placeholderTextColor={C.dim2} selectionColor={C.cyan} allowFontScaling={false} {...rest} placeholder={rest.placeholder ? tr(rest.placeholder) : undefined}
        style={[st.input, error ? { borderColor: C.red } : null, style]} />
      {error ? <T s={error} style={{ fontSize: TS.cap, color: C.red, textAlign: 'right', marginTop: S.xs }} /> : null}
    </View>
  );
}

// ---------- leagues (static table, cached once per session) ----------
let leagueCache: League[] | null = null;
export function useLeagues() {
  const [l, setL] = useState<League[] | null>(leagueCache);
  useEffect(() => {
    if (leagueCache) return;
    let alive = true;
    supabase.from('leagues').select('*').order('sort').then(({ data }) => { if (alive && data) { leagueCache = data as League[]; setL(leagueCache); } }, () => {});
    return () => { alive = false; };
  }, []);
  return l;
}
export const LEAGUE_IMG: Record<string, string> = { bronze: 'medal_bronze', silver: 'medal_silver', gold: 'medal_gold', platinum: 'medal_epic', diamond: 'shield_epic', master: 'shield_star', legend: 'shield_crown' };

// ---------- chat ----------
export function ChatPanel({ link, compact, height }: { link: RoomLink; compact?: boolean; height?: number }) {
  const st2 = useLink(link); const [txt, setTxt] = useState('');
  useEffect(() => { link.chatOpen = true; link.markRead(); return () => { link.chatOpen = false; }; }, [link]);
  useEffect(() => { link.markRead(); }, [st2.chat.length]);
  const data = st2.chat.slice().reverse();
  const send = () => { if (!txt.trim()) return; link.sendChat(txt); setTxt(''); buzz('light'); };
  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ height }}>
      <FlatList inverted data={data} keyExtractor={m => m.id} style={{ flex: 1 }} contentContainerStyle={{ paddingVertical: S.s }}
        renderItem={({ item }) => <ChatRow c={item} mine={item.uid === link.me} compact={compact} />}
        ListEmptyComponent={<View style={{ transform: [{ scaleY: -1 }] }}><T s="هنوز پیامی نیست؛ سلام کن!" style={{ color: C.dim2, fontSize: TS.small, textAlign: 'center', paddingVertical: S.l }} /></View>} />
      <View style={st.chatIn}>
        <Press onPress={send} style={st.send} disabled={!txt.trim()}><Img src={UI2.c_mega} style={{ width: 26, height: 26 }} /></Press>
        <TextInput value={txt} onChangeText={setTxt} onSubmitEditing={send} returnKeyType="send" maxLength={200} placeholder={tr("پیام…")} placeholderTextColor={C.dim2}
          selectionColor={C.cyan} allowFontScaling={false} style={st.chatTxt} blurOnSubmit={false} />
      </View>
    </KeyboardAvoidingView>
  );
}
const ChatRow = memo(function ChatRow({ c, mine, compact }: { c: { name: string; text: string }; mine: boolean; compact?: boolean }) {
  return (
    <View style={{ alignItems: mine ? 'flex-start' : 'flex-end', paddingHorizontal: S.s, marginVertical: 2 }}>
      <View style={[st.bubble, mine ? st.mine : st.theirs, compact && { paddingVertical: 4 }]}>
        {!mine ? <T s={c.name} n={1} style={{ fontFamily: F.bold, fontSize: TS.tiny, color: C.cyan, textAlign: 'right' }} /> : null}
        <T s={c.text} style={{ fontSize: compact ? TS.small : 13, textAlign: 'right' }} />
      </View>
    </View>
  );
});

// ---------- voice controls ----------
export function useVoice(link: RoomLink) {
  const [v, setV] = useState<VoiceState>(link.voice.state);
  useEffect(() => link.voice.on(setV), [link]);
  return v;
}
export function VoiceBar({ link, enabled = true, compact }: { link: RoomLink; enabled?: boolean; compact?: boolean }) {
  const v = useVoice(link); const sup = voiceSupport();
  if (!enabled) return compact ? null : <T s="چت صوتی برای این اتاق خاموش است" style={{ fontSize: TS.cap, color: C.dim2, textAlign: 'right' }} />;
  if (!sup.ok) {
    return (
      <View style={[st.vbar, { opacity: .7 }]}>
        <View style={[st.vbtn, { opacity: .45 }]}><Img src={UI2.c_mega} style={{ width: 22, height: 22 }} /></View>
        {!compact ? <T s={sup.reason} n={2} style={{ flex: 1, fontSize: TS.cap, color: C.dim, textAlign: 'right', marginRight: S.s }} /> : null}
      </View>
    );
  }
  const on = v.status === 'on';
  return (
    <View style={st.vbar}>
      {on ? (
        <>
          <Press onPress={() => link.voice.leave()} style={[st.vbtn, { borderColor: C.red + '88' }]}><T s="✕" style={{ fontSize: 14, color: C.red }} /></Press>
          <Press onPress={() => link.voice.setSpeaker(!v.speaker)} style={[st.vbtn, !v.speaker && st.off]}><T s={v.speaker ? '🔊' : '🔇'} style={{ fontSize: 16 }} /></Press>
          {v.canPublish ? <Press onPress={() => link.voice.setMic(!v.mic)} style={[st.vbtn, v.mic ? { borderColor: C.green, backgroundColor: 'rgba(61,255,168,.15)' } : st.off]}><T s={v.mic ? '🎙' : '🚫'} style={{ fontSize: 16 }} /></Press> : null}
          {!compact ? <T s={v.canPublish ? (v.mic ? 'میکروفون روشن' : 'میکروفون خاموش') : 'فقط شنونده'} n={1} style={{ flex: 1, fontSize: TS.cap, color: C.dim, textAlign: 'right', marginRight: S.s }} /> : null}
        </>
      ) : (
        <>
          <Press onPress={() => link.voice.join()} disabled={v.status === 'connecting'} style={[st.vbtn, { borderColor: C.cyan, width: compact ? 44 : undefined, paddingHorizontal: compact ? 0 : S.m, flexDirection: 'row' }]}>
            {v.status === 'connecting' ? <Spinner /> : <Img src={UI2.c_mega} style={{ width: 22, height: 22 }} />}
            {!compact ? <T s="ورود به چت صوتی" style={{ fontFamily: F.bold, fontSize: TS.small, marginLeft: S.xs }} /> : null}
          </Press>
          {!compact && v.status === 'error' && v.error ? <T s={v.error} n={2} style={{ flex: 1, fontSize: TS.cap, color: C.orange, textAlign: 'right', marginRight: S.s }} /> : null}
        </>
      )}
    </View>
  );
}

export const Divider = () => <View style={{ height: 1, backgroundColor: 'rgba(120,180,255,.14)', marginVertical: S.s }} />;
export const Row = ({ children, style }: { children: React.ReactNode; style?: any }) => <View style={[{ flexDirection: 'row-reverse', alignItems: 'center' }, style]}>{children}</View>;
export const num = (n: number | string) => faNum(n);

export function Card({ children, style, accent, onPress }: { children: React.ReactNode; style?: any; accent?: string; onPress?: () => void }) {
  const body = <Panel style={[{ padding: S.m }, style]} accent={accent || 'transparent'}>{children}</Panel>;
  return onPress ? <Press onPress={onPress} scaleTo={.98}>{body}</Press> : body;
}

export function Tabs<K extends string>({ items, value, onChange }: { items: [K, string][]; value: K; onChange: (k: K) => void }) {
  return (
    <View style={st.tabs}>
      {items.map(([k, l]) => (
        <Pressable key={k} onPress={() => { buzz('light'); onChange(k); }} style={[st.tab, k === value && st.tabOn]} hitSlop={4}>
          <T s={l} n={1} style={{ fontFamily: F.bold, fontSize: TS.small, color: k === value ? '#fff' : C.dim }} />
        </Pressable>
      ))}
    </View>
  );
}

const st = StyleSheet.create({
  header: { position: 'absolute', left: 0, right: 0, top: 0, zIndex: 20, flexDirection: 'row', alignItems: 'center', paddingHorizontal: S.m, paddingBottom: S.m },
  back: { width: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,14,40,.85)', borderWidth: 1, borderColor: C.line, marginRight: S.s },
  badge: { flexDirection: 'row-reverse', alignItems: 'center', height: 22, paddingHorizontal: S.s, borderRadius: 11, borderWidth: 1, marginLeft: S.xs },
  input: { height: 48, borderRadius: 14, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(6,10,30,.85)', color: C.text, paddingHorizontal: S.m, fontFamily: F.fa, fontSize: 15, textAlign: 'right', writingDirection: 'rtl' },
  chatIn: { flexDirection: 'row', alignItems: 'center', padding: S.s, borderTopWidth: 1, borderTopColor: 'rgba(120,180,255,.14)' },
  chatTxt: { flex: 1, height: 44, borderRadius: 22, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(6,10,30,.85)', color: C.text, paddingHorizontal: S.l, fontFamily: F.fa, fontSize: 14, textAlign: 'right', writingDirection: 'rtl', marginLeft: S.s },
  send: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(79,227,255,.18)', borderWidth: 1, borderColor: C.cyan },
  bubble: { maxWidth: '82%', paddingHorizontal: S.m, paddingVertical: 6, borderRadius: 14 },
  mine: { backgroundColor: 'rgba(79,227,255,.16)', borderWidth: 1, borderColor: 'rgba(79,227,255,.35)', borderBottomLeftRadius: 4 },
  theirs: { backgroundColor: 'rgba(20,30,70,.9)', borderWidth: 1, borderColor: C.line, borderBottomRightRadius: 4 },
  vbar: { flexDirection: 'row', alignItems: 'center', minHeight: 44 },
  vbtn: { minWidth: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,14,40,.85)', borderWidth: 1, borderColor: C.line, marginRight: S.s },
  off: { borderColor: C.dim2, backgroundColor: 'rgba(40,40,60,.5)' },
  tabs: { flexDirection: 'row-reverse', height: 44, borderRadius: 22, padding: 3, backgroundColor: 'rgba(6,10,30,.8)', borderWidth: 1, borderColor: C.line },
  tab: { flex: 1, borderRadius: 19, alignItems: 'center', justifyContent: 'center' },
  tabOn: { backgroundColor: 'rgba(79,227,255,.22)', borderWidth: 1, borderColor: C.cyan },
});

// power / accuracy bars (1–10) for a disc
export const StatBars = memo(function StatBars({ power, accuracy, compact }: { power: number; accuracy: number; compact?: boolean }) {
  const row = (label: string, v: number, c: string) => (
    <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginTop: compact ? 2 : 4 }}>
      <T s={label} style={{ fontSize: compact ? 9 : TS.tiny, color: C.dim, width: compact ? 26 : 34, textAlign: 'right' }} />
      <View style={{ flex: 1, flexDirection: 'row-reverse', marginRight: 4 }}>
        {Array.from({ length: 10 }).map((_, i) => <View key={i} style={{ flex: 1, height: compact ? 4 : 6, marginLeft: 1.5, borderRadius: 2, backgroundColor: i < v ? c : 'rgba(255,255,255,.1)' }} />)}
      </View>
      {!compact ? <T s={faNum(v)} style={{ fontFamily: F.bold, fontSize: TS.tiny, color: c, width: 16, textAlign: 'left', marginRight: 4 }} /> : null}
    </View>
  );
  return <View style={{ alignSelf: 'stretch' }}>{row('قدرت', power, C.orange)}{row('دقت', accuracy, C.cyan)}</View>;
});

// small ping indicator: green < 80 ms, yellow < 150 ms, red otherwise
export function PingBadge({ link }: { link: RoomLink }) {
  const ls = useLink(link);
  const r = ls.rtt; const col = r === null ? C.dim : r < 80 ? C.green : r < 150 ? C.gold : C.red;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', height: 24, paddingHorizontal: 8, borderRadius: 12, borderWidth: 1, borderColor: col + '88', backgroundColor: 'rgba(6,10,30,.85)' }}>
      <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: col, marginRight: 5 }} />
      <T s={r === null ? '— ms' : `${r} ms`} style={{ fontFamily: F.head, fontSize: 10, color: col }} />
    </View>
  );
}
