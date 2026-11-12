// Conversation screen (DM / group / channel / club): realtime messages, images, reply, delete own,
// typing indicator over broadcast, read receipts (last_read_at), and an info panel for groups.
import React, { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { Image } from 'expo-image';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI2 } from '../game/assets';
import { Btn, Img, Press, T } from '../ui/kit';
import { Sheet, SheetHandle } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { errFa, rpc, supabase } from '../net/supabase';
import { pickAndUpload } from '../net/media';
import { useNav } from '../nav';
import { Avatar, Badge, Empty, Field, Header, S, Spinner, TS } from '../online/ui';
import { KIND_LABEL, isOnline, timeAgo } from './Social';
import { useOracle } from '../oracle/Oracle';

type Msg = { id: number; conversation_id: string; sender: string | null; body: string | null; image_url: string | null; reply_to: number | null; deleted: boolean; created_at: string };
type Conv = { id: string; kind: 'dm' | 'group' | 'channel' | 'club'; title: string | null; about: string | null; owner: string | null; is_public: boolean; club_id: string | null };
type Member = { user_id: string; role: 'owner' | 'admin' | 'member'; profiles: { username: string; avatar: string; avatar_url: string | null; online_at: string } | null };
const PAGE = 40;

export default function Chat({ id, onBack, toast }: { id: string; onBack: () => void; toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets(); const { uid } = useAuth(); const nav = useNav();
  const [conv, setConv] = useState<Conv | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [msgs, setMsgs] = useState<Msg[] | null>(null);
  const [more, setMore] = useState(true);
  const [txt, setTxt] = useState('');
  const [reply, setReply] = useState<Msg | null>(null);
  const [typing, setTyping] = useState<Record<string, number>>({});
  const [sending, setSending] = useState(false);
  const [menu, setMenu] = useState<Msg | null>(null);
  const [info, setInfo] = useState(false);
  const [viewer, setViewer] = useState<string | null>(null);
  const ch = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const lastTyping = useRef(0);
  const infoRef = useRef<SheetHandle>(null);
  const oracle = useOracle();
  useEffect(() => { oracle.setQuiet('chat', true); return () => oracle.setQuiet('chat', false); }, []);

  const byId = useMemo(() => { const m: Record<string, Member> = {}; for (const x of members) m[x.user_id] = x; return m; }, [members]);
  const me = uid ? byId[uid] : undefined;
  const peer = conv?.kind === 'dm' ? members.find(m => m.user_id !== uid) : undefined;
  const canPost = !!me && (conv?.kind !== 'channel' || me.role === 'owner' || me.role === 'admin');

  const markRead = useCallback(() => { if (uid) supabase.from('conversation_members').update({ last_read_at: new Date().toISOString() }).eq('conversation_id', id).eq('user_id', uid).then(() => {}, () => {}); }, [id, uid]);
  const loadMeta = useCallback(async () => {
    const [c, m] = await Promise.all([
      supabase.from('conversations').select('*').eq('id', id).maybeSingle(),
      supabase.from('conversation_members').select('user_id, role, profiles(username, avatar, avatar_url, online_at)').eq('conversation_id', id).limit(500),
    ]);
    if (c.data) setConv(c.data as Conv); if (m.data) setMembers(m.data as any);
  }, [id]);
  const loadMsgs = useCallback(async (before?: string) => {
    let q = supabase.from('messages').select('*').eq('conversation_id', id).order('created_at', { ascending: false }).limit(PAGE);
    if (before) q = q.lt('created_at', before);
    const { data, error } = await q;
    if (error) { toast(errFa(error), 'err'); if (!before) setMsgs([]); return; }
    const rows = (data || []) as Msg[]; setMore(rows.length === PAGE);
    setMsgs(prev => (before ? [...(prev || []), ...rows] : rows));
  }, [id]);

  useEffect(() => {
    loadMeta(); loadMsgs(); markRead();
    const c = supabase.channel(`conv:${id}`, { config: { broadcast: { self: false } } })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${id}` }, p => {
        const m = p.new as Msg;
        setMsgs(prev => (prev && prev.some(x => x.id === m.id) ? prev : [m, ...(prev || [])]));
        if (m.sender !== uid) { sfx('chat'); markRead(); }
        if (m.sender) setTyping(t => { const n = { ...t }; delete n[m.sender!]; return n; });
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages', filter: `conversation_id=eq.${id}` }, p => {
        const m = p.new as Msg; setMsgs(prev => prev && prev.map(x => (x.id === m.id ? m : x)));
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversation_members', filter: `conversation_id=eq.${id}` }, () => loadMeta())
      .on('broadcast', { event: 'typing' }, ({ payload }) => { const u = (payload as any)?.u; if (u && u !== uid) setTyping(t => ({ ...t, [u]: Date.now() })); })
      .subscribe();
    ch.current = c;
    const tick = setInterval(() => setTyping(t => { const now = Date.now(); let ch2 = false; const n: Record<string, number> = {}; for (const k in t) if (now - t[k] < 4000) n[k] = t[k]; else ch2 = true; return ch2 ? n : t; }), 1500);
    return () => { clearInterval(tick); supabase.removeChannel(c); ch.current = null; markRead(); };
  }, [id, uid]);

  const onType = (v: string) => {
    setTxt(v);
    const now = Date.now(); if (v && now - lastTyping.current > 2500) { lastTyping.current = now; ch.current?.send({ type: 'broadcast', event: 'typing', payload: { u: uid } }).catch(() => {}); }
  };
  const send = async (image_url?: string) => {
    const body = txt.trim();
    if (!uid || (!body && !image_url) || sending) return;
    setSending(true);
    const { data, error } = await supabase.from('messages').insert({ conversation_id: id, sender: uid, body: body ? body.slice(0, 2000) : null, image_url: image_url || null, reply_to: reply?.id ?? null }).select().single();
    setSending(false);
    if (error) { toast(errFa(error), 'err'); return; }
    setTxt(''); setReply(null); buzz('light');
    setMsgs(prev => (prev && prev.some(x => x.id === (data as Msg).id) ? prev : [data as Msg, ...(prev || [])]));
  };
  const sendImage = async () => {
    if (!uid) return; setSending(true);
    const r = await pickAndUpload('chat', uid, { size: 1280 }); setSending(false);
    if (!r.ok) { if (!r.cancelled) toast(r.error, 'err'); return; }
    send(r.url);
  };
  const del = async (m: Msg) => { setMenu(null); const { error } = await supabase.from('messages').update({ deleted: true, body: null }).eq('id', m.id); if (error) toast(errFa(error), 'err'); };

  const title = conv?.kind === 'dm' ? peer?.profiles?.username || 'گفتگو' : conv?.title || 'گفتگو';
  const typers = Object.keys(typing).map(u => byId[u]?.profiles?.username).filter(Boolean);
  const msgById = useMemo(() => { const m: Record<number, Msg> = {}; for (const x of msgs || []) m[x.id] = x; return m; }, [msgs]);

  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      <Header title={title} en={conv ? (conv.kind === 'dm' ? (isOnline(peer?.profiles?.online_at) ? 'ONLINE' : 'DIRECT') : `${KIND_LABEL[conv.kind]} · ${fa(members.length)} عضو`) : ''} onBack={onBack}
        right={conv?.kind === 'dm' && peer ? <Press onPress={() => nav.openProfile(peer.user_id)}><Avatar avatar={peer.profiles?.avatar} url={peer.profiles?.avatar_url} size={40} ring={isOnline(peer.profiles?.online_at) ? C.green : C.line} /></Press>
          : conv ? <Press onPress={() => setInfo(true)} style={st.hBtn}><T s="ⓘ" style={{ fontSize: 20, color: C.cyan }} /></Press> : null} />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {!msgs ? <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner /></View> : (
          <FlatList inverted data={msgs} keyExtractor={m => String(m.id)} style={{ flex: 1 }}
            contentContainerStyle={{ paddingTop: S.s, paddingBottom: ins.top + 76 }}
            renderItem={({ item, index }) => {
              const prev = msgs[index + 1];
              return <Bubble m={item} mine={item.sender === uid} showName={conv?.kind !== 'dm' && item.sender !== uid && prev?.sender !== item.sender}
                name={item.sender ? byId[item.sender]?.profiles?.username || '…' : ''} replyTo={item.reply_to ? msgById[item.reply_to] : undefined} replyName={(rid: string | null) => (rid ? byId[rid]?.profiles?.username || '' : '')}
                onLong={() => !item.deleted && setMenu(item)} onImage={setViewer} />;
            }}
            onEndReached={() => { if (more && msgs.length) loadMsgs(msgs[msgs.length - 1].created_at); }} onEndReachedThreshold={.4}
            ListEmptyComponent={<View style={{ transform: [{ scaleY: -1 }] }}><Empty img={UI2.c_mega} title="اولین پیام را بفرست!" /></View>}
            initialNumToRender={20} windowSize={11} keyboardShouldPersistTaps="handled" />
        )}
        {typers.length ? <T s={`${typers.join('، ')} در حال نوشتن…`} n={1} style={{ fontSize: TS.cap, color: C.cyan, textAlign: 'right', paddingHorizontal: S.l, paddingBottom: 2 }} /> : null}
        {reply ? (
          <View style={st.replyBar}>
            <Press onPress={() => setReply(null)} style={{ width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }}><T s="✕" style={{ color: C.dim }} /></Press>
            <View style={{ flex: 1, alignItems: 'flex-end' }}>
              <T s={`پاسخ به ${reply.sender ? byId[reply.sender]?.profiles?.username || '' : ''}`} style={{ fontSize: TS.tiny, color: C.cyan }} />
              <T s={reply.body || '📷 عکس'} n={1} style={{ fontSize: TS.small }} />
            </View>
          </View>
        ) : null}
        {canPost ? (
          <View style={[st.input, { paddingBottom: Math.max(ins.bottom, S.s) }]}>
            <Press onPress={() => send()} disabled={!txt.trim() || sending} style={st.send}>{sending ? <Spinner /> : <Img src={UI2.c_mega} style={{ width: 24, height: 24 }} />}</Press>
            <TextInput value={txt} onChangeText={onType} placeholder="پیام…" placeholderTextColor={C.dim2} multiline maxLength={2000} allowFontScaling={false}
              style={st.txt} selectionColor={C.cyan} />
            <Press onPress={sendImage} disabled={sending} style={st.attach}><T s="🖼" style={{ fontSize: 20 }} /></Press>
          </View>
        ) : conv && !me && conv.is_public ? (
          <View style={{ padding: S.m, paddingBottom: Math.max(ins.bottom, S.m) }}>
            <Btn label="پیوستن" colors={G.green} onPress={async () => { try { await rpc('join_conversation', { p_conv: id }); loadMeta(); } catch (e) { toast(errFa(e), 'err'); } }} />
          </View>
        ) : conv ? <T s={conv.kind === 'channel' ? 'فقط مدیران کانال می‌توانند پیام بفرستند' : 'امکان ارسال پیام نیست'} style={{ textAlign: 'center', color: C.dim, fontSize: TS.small, padding: S.m, paddingBottom: Math.max(ins.bottom, S.m) }} /> : null}
      </KeyboardAvoidingView>

      {menu ? (
        <Press onPress={() => setMenu(null)} style={st.ovl} sound={false} scaleTo={1}>
          <View style={st.menu}>
            {canPost ? <MenuItem label="پاسخ" onPress={() => { setReply(menu); setMenu(null); }} /> : null}
            {menu.sender && menu.sender !== uid ? <MenuItem label="مشاهده‌ی پروفایل" onPress={() => { const s2 = menu.sender!; setMenu(null); nav.openProfile(s2); }} /> : null}
            {menu.sender === uid ? <MenuItem label="حذف پیام" color={C.red} onPress={() => del(menu)} /> : null}
            <MenuItem label="انصراف" color={C.dim} onPress={() => setMenu(null)} />
          </View>
        </Press>
      ) : null}
      {viewer ? (
        <Press onPress={() => setViewer(null)} style={st.ovl} sound={false} scaleTo={1}>
          <Image source={{ uri: viewer }} style={{ width: '94%', height: '70%' }} contentFit="contain" />
        </Press>
      ) : null}
      {info && conv ? (
        <Sheet ref={infoRef} onClosed={() => setInfo(false)} title={conv.title || KIND_LABEL[conv.kind]} en={`${KIND_LABEL[conv.kind]} INFO`} height={.85}>
          <ConvInfo conv={conv} members={members} myRole={me?.role} toast={toast} onChanged={loadMeta} onLeft={() => { infoRef.current?.close(); onBack(); }} />
        </Sheet>
      ) : null}
    </View>
  );
}

const MenuItem = ({ label, onPress, color }: { label: string; onPress: () => void; color?: string }) => (
  <Press onPress={onPress} style={{ height: 52, justifyContent: 'center', paddingHorizontal: S.l }}><T s={label} style={{ fontFamily: F.bold, fontSize: TS.body, color: color || C.text, textAlign: 'right' }} /></Press>
);

const Bubble = memo(function Bubble({ m, mine, showName, name, replyTo, replyName, onLong, onImage }: { m: Msg; mine: boolean; showName: boolean; name: string; replyTo?: Msg; replyName: (u: string | null) => string; onLong: () => void; onImage: (u: string) => void }) {
  return (
    <View style={{ alignItems: mine ? 'flex-start' : 'flex-end', paddingHorizontal: S.m, marginVertical: 2 }}>
      <Press onLongPress={onLong} onPress={m.image_url ? () => onImage(m.image_url!) : undefined} sound={false} scaleTo={.98} haptic={false}>
        <View style={[st.bubble, mine ? st.mine : st.theirs, m.deleted && { opacity: .5 }]}>
          {showName ? <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: TS.tiny, color: C.cyan, textAlign: 'right' }} /> : null}
          {replyTo ? <View style={st.quote}><T s={replyName(replyTo.sender)} style={{ fontSize: 10, color: C.cyan, textAlign: 'right' }} /><T s={replyTo.deleted ? 'پیام حذف شده' : replyTo.body || '📷 عکس'} n={1} style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right' }} /></View> : null}
          {m.deleted ? <T s="🚫 این پیام حذف شد" style={{ fontSize: TS.small, color: C.dim }} /> : (
            <>
              {m.image_url ? <Image source={{ uri: m.image_url }} style={{ width: 220, height: 220, borderRadius: 12, marginVertical: 2 }} contentFit="cover" transition={150} cachePolicy="memory-disk" /> : null}
              {m.body ? <T s={m.body} style={{ fontSize: 14, textAlign: 'right', lineHeight: 22 }} /> : null}
            </>
          )}
          <T s={timeAgo(m.created_at)} style={{ fontSize: 9, color: C.dim2, textAlign: mine ? 'left' : 'right', marginTop: 2 }} />
        </View>
      </Press>
    </View>
  );
});

function ConvInfo({ conv, members, myRole, toast, onChanged, onLeft }: { conv: Conv; members: Member[]; myRole?: string; toast: (m: string, k?: string) => void; onChanged: () => void; onLeft: () => void }) {
  const { uid } = useAuth(); const nav = useNav();
  const [q, setQ] = useState(''); const [found, setFound] = useState<any[]>([]);
  const admin = myRole === 'owner' || myRole === 'admin';
  useEffect(() => {
    const term = q.trim(); if (term.length < 2) { setFound([]); return; }
    const t = setTimeout(async () => { const { data } = await supabase.from('profiles').select('id, username, avatar, avatar_url').ilike('username', `%${term.replace(/[%_]/g, '')}%`).limit(10); setFound(data || []); }, 300);
    return () => clearTimeout(t);
  }, [q]);
  const act = async (u: string, a: 'add' | 'remove' | 'promote' | 'demote') => { try { await rpc('manage_member', { p_conv: conv.id, p_user: u, p_action: a }); onChanged(); buzz('light'); } catch (e) { toast(errFa(e), 'err'); } };
  const leave = async () => { try { await rpc('leave_conversation', { p_conv: conv.id }); toast('خارج شدی', 'ok'); onLeft(); } catch (e) { toast(errFa(e), 'err'); } };
  return (
    <ScrollView contentContainerStyle={{ padding: S.l, paddingBottom: S.xl * 2 }} keyboardShouldPersistTaps="handled">
      {conv.about ? <T s={conv.about} style={{ color: C.dim, textAlign: 'right', marginBottom: S.m }} /> : null}
      {admin && conv.kind !== 'club' ? (
        <>
          <Field label="افزودن عضو" value={q} onChangeText={setQ} placeholder="نام کاربری…" autoCapitalize="none" />
          {found.filter(f => !members.some(m => m.user_id === f.id)).map(f => (
            <View key={f.id} style={st.mrow}>
              <Avatar avatar={f.avatar} url={f.avatar_url} size={36} />
              <T s={f.username} n={1} style={{ flex: 1, marginRight: S.s, textAlign: 'right' }} />
              <Press onPress={() => { act(f.id, 'add'); setQ(''); }} style={st.small}><T s="افزودن" style={{ color: C.green, fontSize: TS.small }} /></Press>
            </View>
          ))}
        </>
      ) : null}
      <T s={`اعضا (${fa(members.length)})`} style={{ fontFamily: F.bold, fontSize: TS.h, textAlign: 'right', marginVertical: S.s }} />
      {members.map(m => (
        <View key={m.user_id} style={st.mrow}>
          <Press onPress={() => nav.openProfile(m.user_id)}><Avatar avatar={m.profiles?.avatar} url={m.profiles?.avatar_url} size={40} ring={isOnline(m.profiles?.online_at) ? C.green : C.line} /></Press>
          <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
            <T s={(m.profiles?.username || '…') + (m.user_id === uid ? ' (تو)' : '')} n={1} style={{ fontFamily: F.bold }} />
            {m.role !== 'member' ? <Badge label={m.role === 'owner' ? 'مالک' : 'مدیر'} color={m.role === 'owner' ? C.gold : C.cyan} /> : null}
          </View>
          {myRole === 'owner' && m.user_id !== uid && conv.kind !== 'club' ? (
            <Press onPress={() => act(m.user_id, m.role === 'admin' ? 'demote' : 'promote')} style={st.small}><T s={m.role === 'admin' ? 'برکناری' : 'مدیر کن'} style={{ fontSize: TS.cap, color: C.cyan }} /></Press>
          ) : null}
          {admin && m.user_id !== uid && m.role !== 'owner' && conv.kind !== 'club' ? (
            <Press onPress={() => act(m.user_id, 'remove')} style={st.small}><T s="حذف" style={{ fontSize: TS.cap, color: C.red }} /></Press>
          ) : null}
        </View>
      ))}
      {conv.kind !== 'club' && conv.kind !== 'dm' ? <Btn label="خروج از گفتگو" small colors={G.red} onPress={leave} style={{ marginTop: S.l }} /> : null}
    </ScrollView>
  );
}

const st = StyleSheet.create({
  hBtn: { width: 44, height: 44, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,14,40,.85)', borderWidth: 1, borderColor: C.line },
  bubble: { maxWidth: 290, paddingHorizontal: S.m, paddingVertical: 6, borderRadius: 16 },
  mine: { backgroundColor: 'rgba(79,227,255,.16)', borderWidth: 1, borderColor: 'rgba(79,227,255,.35)', borderBottomLeftRadius: 4 },
  theirs: { backgroundColor: 'rgba(20,30,70,.92)', borderWidth: 1, borderColor: C.line, borderBottomRightRadius: 4 },
  quote: { borderRightWidth: 3, borderRightColor: C.cyan, paddingRight: 6, marginBottom: 4, backgroundColor: 'rgba(0,0,0,.2)', borderRadius: 6, paddingVertical: 2 },
  input: { flexDirection: 'row', alignItems: 'flex-end', paddingHorizontal: S.s, paddingTop: S.s, borderTopWidth: 1, borderTopColor: C.line, backgroundColor: 'rgba(4,8,24,.96)' },
  txt: { flex: 1, minHeight: 44, maxHeight: 120, borderRadius: 22, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(6,10,30,.85)', color: C.text, paddingHorizontal: S.l, paddingTop: 11, paddingBottom: 11, fontFamily: F.fa, fontSize: 14, textAlign: 'right', writingDirection: 'rtl', marginHorizontal: S.s },
  send: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(79,227,255,.18)', borderWidth: 1, borderColor: C.cyan },
  attach: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: C.line },
  replyBar: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: S.m, borderTopWidth: 1, borderTopColor: C.line, backgroundColor: 'rgba(10,16,44,.95)' },
  ovl: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(1,3,12,.82)', alignItems: 'center', justifyContent: 'center', zIndex: 50 },
  menu: { width: 260, borderRadius: 18, overflow: 'hidden', backgroundColor: '#0e1640', borderWidth: 1, borderColor: C.line },
  mrow: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 56, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,.08)' },
  small: { height: 44, paddingHorizontal: S.s, justifyContent: 'center' },
});
