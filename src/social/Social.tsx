// Social tab: messages (inbox + user search + discover groups/channels), clubs, friends (following/followers).
import React, { memo, useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { UI2 } from '../game/assets';
import { Btn, Img, Panel, Press, Segment, T, Toggle } from '../ui/kit';
import { Sheet, SheetHandle } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { errFa, rpc, supabase } from '../net/supabase';
import { useNav } from '../nav';
import { Avatar, Badge, Empty, ErrorState, Field, S, Skeleton, Spinner, TS, Tabs, discImg } from '../online/ui';

export type InboxRow = {
  id: string; kind: 'dm' | 'group' | 'channel' | 'club'; title: string | null; avatar_url: string | null; club_id: string | null; last_message_at: string;
  role: string; muted: boolean; last_message: { body: string | null; image_url: string | null; sender: string; created_at: string } | null; unread: number;
  peer: { id: string; username: string; avatar: string; avatar_url: string | null; online_at: string } | null; members: number;
};
export const isOnline = (at?: string | null) => !!at && Date.now() - new Date(at).getTime() < 3 * 60000;
export const timeAgo = (iso?: string | null) => {
  if (!iso) return ''; const d = (Date.now() - new Date(iso).getTime()) / 1000;
  return d < 60 ? 'الان' : d < 3600 ? `${fa(Math.floor(d / 60))} دقیقه` : d < 86400 ? `${fa(Math.floor(d / 3600))} ساعت` : `${fa(Math.floor(d / 86400))} روز`;
};
export const KIND_LABEL: Record<string, string> = { dm: 'گفتگو', group: 'گروه', channel: 'کانال', club: 'باشگاه' };

export default function Social({ top, bottom, toast }: { top: number; bottom: number; toast: (m: string, k?: string) => void }) {
  const auth = useAuth();
  const [tab, setTab] = useState<'msg' | 'club' | 'friends'>('msg');
  const [busy, setBusy] = useState(false);
  if (!auth.uid) {
    return (
      <View style={{ flex: 1, paddingTop: top, paddingBottom: bottom, justifyContent: 'center' }}>
        <Empty img={UI2.c_profile} title="اجتماعی" sub="برای پیام، باشگاه و دوستان وارد بخش آنلاین شو (مهمان هم می‌شود)"
          action={busy ? '…' : 'ورود به‌عنوان مهمان'} onAction={async () => { setBusy(true); try { await auth.ensure(); } catch { toast('اتصال برقرار نشد', 'err'); } finally { setBusy(false); } }} />
      </View>
    );
  }
  return (
    <View style={{ flex: 1, paddingTop: top }}>
      <View style={{ paddingHorizontal: S.l, marginBottom: S.s }}>
        <Tabs items={[['msg', 'پیام‌ها'], ['club', 'باشگاه‌ها'], ['friends', 'دوستان']]} value={tab} onChange={setTab} />
      </View>
      {tab === 'msg' ? <Messages bottom={bottom} toast={toast} /> : tab === 'club' ? <Clubs bottom={bottom} toast={toast} /> : <Friends bottom={bottom} />}
    </View>
  );
}

// ======================= messages =======================
function Messages({ bottom, toast }: { bottom: number; toast: (m: string, k?: string) => void }) {
  const { uid } = useAuth(); const nav = useNav();
  const [rows, setRows] = useState<InboxRow[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [found, setFound] = useState<any[] | null>(null);
  const [sheet, setSheet] = useState<null | 'new' | 'discover'>(null);
  const [refreshing, setRefreshing] = useState(false);
  const sheetRef = useRef<SheetHandle>(null);
  const load = useCallback(async () => {
    const { data, error } = await supabase.from('inbox').select('*').order('last_message_at', { ascending: false }).limit(100);
    if (error) { setErr(errFa(error)); return; } setErr(null); setRows(data as InboxRow[]);
  }, []);
  useEffect(() => {
    load();
    let t: ReturnType<typeof setTimeout> | null = null;
    const soon = () => { if (t) clearTimeout(t); t = setTimeout(load, 400); };
    // RLS limits message events to conversations I belong to
    const ch = supabase.channel(`inbox:${uid}`).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, soon)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversation_members', filter: `user_id=eq.${uid}` }, soon).subscribe();
    return () => { if (t) clearTimeout(t); supabase.removeChannel(ch); };
  }, [uid, load]);
  useEffect(() => {
    const term = q.trim(); if (term.length < 2) { setFound(null); return; }
    const id = setTimeout(async () => {
      const { data } = await supabase.from('profiles').select('id, username, avatar, avatar_url, level, online_at').ilike('username', `%${term.replace(/[%_]/g, '')}%`).neq('id', uid!).limit(20);
      setFound(data || []);
    }, 300);
    return () => clearTimeout(id);
  }, [q]);
  const dm = async (id: string) => { try { const cid = await rpc<string>('open_dm', { p_user: id }); setQ(''); nav.openChat(cid); } catch (e) { toast(errFa(e), 'err'); } };

  const header = (
    <View style={{ paddingHorizontal: S.l }}>
      <Field value={q} onChangeText={setQ} placeholder="جستجوی بازیکن با نام کاربری…" autoCapitalize="none" />
      {found ? (
        <View style={{ marginBottom: S.m }}>
          {found.length ? found.map(p => (
            <View key={p.id} style={st.row}>
              <Press onPress={() => nav.openProfile(p.id)}><Avatar avatar={p.avatar} url={p.avatar_url} size={40} ring={isOnline(p.online_at) ? C.green : C.line} /></Press>
              <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}><T s={p.username} n={1} style={{ fontFamily: F.bold, fontSize: TS.body }} /><T s={`سطح ${fa(p.level)}`} style={{ fontSize: TS.tiny, color: C.dim }} /></View>
              <Press onPress={() => dm(p.id)} style={st.pill}><T s="پیام" style={{ fontFamily: F.bold, fontSize: TS.small, color: C.cyan }} /></Press>
            </View>
          )) : <T s="کسی پیدا نشد" style={{ color: C.dim, textAlign: 'center', marginBottom: S.s }} />}
        </View>
      ) : null}
      <View style={{ flexDirection: 'row-reverse', marginBottom: S.m }}>
        <Btn label="گروه / کانال جدید" small colors={G.green} onPress={() => setSheet('new')} style={{ flex: 1, marginLeft: S.s }} />
        <Btn label="کشف گروه‌ها" small colors={G.dark} onPress={() => setSheet('discover')} style={{ flex: 1 }} />
      </View>
    </View>
  );
  return (
    <View style={{ flex: 1 }}>
      <FlatList data={rows || []} keyExtractor={r => r.id} ListHeaderComponent={header} keyboardShouldPersistTaps="handled"
        renderItem={({ item }) => <InboxItem r={item} onPress={() => nav.openChat(item.id)} />}
        ListEmptyComponent={err ? <ErrorState msg={err} onRetry={load} /> : !rows ? <Skeleton rows={5} h={64} /> : <Empty img={UI2.c_mega} title="هنوز گفتگویی نداری" sub="یک بازیکن را جستجو کن یا به یک گروه بپیوند" />}
        contentContainerStyle={{ paddingBottom: bottom + S.l }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} tintColor={C.cyan} />}
        showsVerticalScrollIndicator={false} />
      {sheet ? (
        <Sheet ref={sheetRef} onClosed={() => setSheet(null)} title={sheet === 'new' ? 'گروه یا کانال جدید' : 'کشف گروه‌ها و کانال‌ها'} en={sheet === 'new' ? 'NEW CONVERSATION' : 'DISCOVER'} height={.82}>
          {sheet === 'new' ? <NewConv toast={toast} onDone={id => { sheetRef.current?.close(); nav.openChat(id); }} /> : <Discover toast={toast} onOpen={id => { sheetRef.current?.close(); nav.openChat(id); }} />}
        </Sheet>
      ) : null}
    </View>
  );
}

const InboxItem = memo(function InboxItem({ r, onPress }: { r: InboxRow; onPress: () => void }) {
  const title = r.kind === 'dm' ? r.peer?.username || 'گفتگو' : r.title || KIND_LABEL[r.kind];
  const lm = r.last_message;
  return (
    <View style={{ paddingHorizontal: S.l }}>
      <Press onPress={onPress} scaleTo={.98}>
        <View style={[st.row, { height: 72 }]}>
          <View>
            {r.kind === 'dm' ? <Avatar avatar={r.peer?.avatar} url={r.peer?.avatar_url} size={48} ring={isOnline(r.peer?.online_at) ? C.green : C.line} />
              : <View style={[st.convIcon, { borderColor: r.kind === 'club' ? C.gold : r.kind === 'channel' ? C.violet : C.cyan }]}><Img src={r.avatar_url ? { uri: r.avatar_url } : r.kind === 'club' ? UI2.x_shield : r.kind === 'channel' ? UI2.c_mega : UI2.x_team} style={{ width: 32, height: 32 }} /></View>}
            {r.kind === 'dm' && isOnline(r.peer?.online_at) ? <View style={st.on} /> : null}
          </View>
          <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
            <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
              <T s={title} n={1} style={{ fontFamily: F.bold, fontSize: TS.body, maxWidth: 170 }} />
              {r.kind !== 'dm' ? <Badge label={KIND_LABEL[r.kind]} color={r.kind === 'club' ? C.gold : r.kind === 'channel' ? C.violet : C.cyan} /> : null}
            </View>
            <T s={lm ? (lm.image_url && !lm.body ? '📷 عکس' : lm.body || '') : 'بدون پیام'} n={1} style={{ fontSize: TS.small, color: r.unread ? C.text : C.dim, marginTop: 2 }} />
          </View>
          <View style={{ alignItems: 'center', minWidth: 48 }}>
            <T s={timeAgo(lm?.created_at || r.last_message_at)} style={{ fontSize: TS.tiny, color: C.dim }} />
            {r.unread ? <View style={st.unread}><T s={fa(Math.min(99, r.unread))} style={{ fontFamily: F.bold, fontSize: 10, color: '#fff' }} /></View> : null}
          </View>
        </View>
      </Press>
    </View>
  );
});

function NewConv({ toast, onDone }: { toast: (m: string, k?: string) => void; onDone: (id: string) => void }) {
  const [kind, setKind] = useState<'group' | 'channel'>('group');
  const [title, setTitle] = useState(''); const [about, setAbout] = useState(''); const [pub, setPub] = useState(true); const [busy, setBusy] = useState(false);
  const go = async () => {
    if (title.trim().length < 2) { toast('عنوان لازم است', 'err'); return; }
    setBusy(true);
    try { const id = await rpc<string>('create_conversation', { p_kind: kind, p_title: title.trim(), p_about: about.trim() || null, p_public: pub, p_members: [] }); sfx('ready'); onDone(id); }
    catch (e) { toast(errFa(e), 'err'); } finally { setBusy(false); }
  };
  return (
    <ScrollView contentContainerStyle={{ padding: S.l }} keyboardShouldPersistTaps="handled">
      <Segment value={kind} onChange={setKind} items={[['group', 'گروه'], ['channel', 'کانال']]} />
      <T s={kind === 'group' ? 'در گروه همه‌ی اعضا پیام می‌فرستند.' : 'در کانال فقط مالک و مدیرها پیام می‌فرستند.'} style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right', marginTop: S.s, marginBottom: S.m }} />
      <Field label="عنوان" value={title} onChangeText={setTitle} maxLength={40} />
      <Field label="توضیح (اختیاری)" value={about} onChangeText={setAbout} maxLength={200} multiline style={{ height: 80, textAlignVertical: 'top', paddingTop: S.s }} />
      <View style={{ flexDirection: 'row-reverse', alignItems: 'center', minHeight: 56 }}>
        <View style={{ flex: 1, alignItems: 'flex-end' }}><T s="عمومی" style={{ fontFamily: F.bold }} /><T s="در بخش «کشف» دیده شود و همه بتوانند بپیوندند" style={{ fontSize: TS.cap, color: C.dim }} /></View>
        <Toggle on={pub} onChange={setPub} />
      </View>
      <Btn label={busy ? '…' : 'ساختن'} onPress={go} disabled={busy} colors={G.green} style={{ marginTop: S.l }} />
    </ScrollView>
  );
}

function Discover({ toast, onOpen }: { toast: (m: string, k?: string) => void; onOpen: (id: string) => void }) {
  const [rows, setRows] = useState<any[] | null>(null);
  useEffect(() => { supabase.from('public_conversations').select('*').order('members', { ascending: false }).limit(50).then(({ data }) => setRows(data || []), () => setRows([])); }, []);
  const join = async (id: string) => { try { await rpc('join_conversation', { p_conv: id }); sfx('join'); onOpen(id); } catch (e) { toast(errFa(e), 'err'); } };
  if (!rows) return <Skeleton rows={4} />;
  if (!rows.length) return <Empty title="هنوز گروه عمومی‌ای نیست" sub="اولین گروه را خودت بساز" />;
  return (
    <FlatList data={rows} keyExtractor={r => r.id} contentContainerStyle={{ padding: S.l }}
      renderItem={({ item }) => (
        <View style={st.row}>
          <View style={[st.convIcon, { borderColor: item.kind === 'channel' ? C.violet : C.cyan }]}><Img src={item.kind === 'channel' ? UI2.c_mega : UI2.x_team} style={{ width: 30, height: 30 }} /></View>
          <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
            <T s={item.title} n={1} style={{ fontFamily: F.bold }} />
            <T s={`${KIND_LABEL[item.kind]} · ${fa(item.members)} عضو${item.about ? ' · ' + item.about : ''}`} n={1} style={{ fontSize: TS.cap, color: C.dim }} />
          </View>
          <Press onPress={() => join(item.id)} style={st.pill}><T s="پیوستن" style={{ fontFamily: F.bold, fontSize: TS.small, color: C.green }} /></Press>
        </View>
      )} />
  );
}

// ======================= clubs =======================
export const CLUB_EMBLEMS = Array.from({ length: 18 }, (_, i) => `leg${i}`);
function Clubs({ bottom, toast }: { bottom: number; toast: (m: string, k?: string) => void }) {
  const { profile } = useAuth(); const nav = useNav();
  const [rows, setRows] = useState<any[] | null>(null);
  const [q, setQ] = useState('');
  const [sheet, setSheet] = useState(false);
  const sheetRef = useRef<SheetHandle>(null);
  const load = useCallback(async () => {
    let qq = supabase.from('club_list').select('*').order('power', { ascending: false }).limit(50);
    const term = q.trim().replace(/[%_,()]/g, ''); if (term) qq = qq.or(`name.ilike.%${term}%,tag.ilike.%${term}%`);
    const { data } = await qq; setRows(data || []);
  }, [q]);
  useEffect(() => { const id = setTimeout(load, 250); return () => clearTimeout(id); }, [load]);
  return (
    <View style={{ flex: 1 }}>
      <FlatList data={rows || []} keyExtractor={r => r.id} keyboardShouldPersistTaps="handled"
        ListHeaderComponent={
          <View style={{ paddingHorizontal: S.l }}>
            {profile?.club_id ? <Btn label="باشگاه من" colors={G.gold} small onPress={() => nav.openClub(profile.club_id!)} style={{ marginBottom: S.s }} />
              : <Btn label="ساخت باشگاه (۵۰ الماس)" colors={G.green} small onPress={() => setSheet(true)} style={{ marginBottom: S.s }} />}
            <Field value={q} onChangeText={setQ} placeholder="جستجوی نام یا تگ باشگاه…" autoCapitalize="characters" />
            <T s="برترین باشگاه‌ها" style={{ fontFamily: F.bold, fontSize: TS.h, textAlign: 'right', marginBottom: S.s }} />
          </View>}
        renderItem={({ item, index }) => (
          <View style={{ paddingHorizontal: S.l }}>
            <Press onPress={() => nav.openClub(item.id)} scaleTo={.98}>
              <View style={[st.row, { height: 70 }, item.id === profile?.club_id && { borderColor: C.gold }]}>
                <T s={fa(index + 1)} style={{ width: 28, fontFamily: F.title, color: index < 3 ? C.gold : C.dim, textAlign: 'center' }} />
                <Img src={discImg(item.emblem)} style={{ width: 46, height: 46 }} />
                <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
                  <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}><T s={item.name} n={1} style={{ fontFamily: F.bold, maxWidth: 150 }} /><Badge label={item.tag} color={C.gold} /></View>
                  <T s={`${fa(item.members)}/${fa(item.max_members)} عضو · ${item.join_policy === 'open' ? 'آزاد' : item.join_policy === 'request' ? 'با درخواست' : 'فقط دعوت'}`} style={{ fontSize: TS.cap, color: C.dim }} />
                </View>
                <View style={{ alignItems: 'center', width: 64 }}><T s={fa(item.power)} style={{ fontFamily: F.title, fontSize: 13, color: C.orange }} /><T s="قدرت" style={{ fontSize: 9, color: C.dim }} /></View>
              </View>
            </Press>
          </View>
        )}
        ListEmptyComponent={!rows ? <Skeleton rows={5} h={70} /> : <Empty img={UI2.x_shield} title="باشگاهی پیدا نشد" />}
        contentContainerStyle={{ paddingBottom: bottom + S.l }} showsVerticalScrollIndicator={false} />
      {sheet ? (
        <Sheet ref={sheetRef} onClosed={() => setSheet(false)} title="ساخت باشگاه" en="NEW CLUB" accent={C.gold} height={.9}>
          <CreateClub toast={toast} onDone={id => { sheetRef.current?.close(); nav.openClub(id); }} />
        </Sheet>
      ) : null}
    </View>
  );
}

function CreateClub({ toast, onDone }: { toast: (m: string, k?: string) => void; onDone: (id: string) => void }) {
  const { profile } = useAuth();
  const [name, setName] = useState(''); const [tag, setTag] = useState(''); const [desc, setDesc] = useState('');
  const [emblem, setEmblem] = useState('leg0'); const [policy, setPolicy] = useState<'open' | 'request' | 'invite'>('open'); const [busy, setBusy] = useState(false);
  const go = async () => {
    if (name.trim().length < 3 || name.trim().length > 24) { toast('نام باشگاه ۳ تا ۲۴ کاراکتر', 'err'); return; }
    if (!/^[A-Z0-9]{2,5}$/.test(tag)) { toast('تگ: ۲ تا ۵ حرف/عدد انگلیسی بزرگ', 'err'); return; }
    if ((profile?.gems ?? 0) < 50) { toast('۵۰ الماس لازم داری', 'err'); return; }
    setBusy(true);
    try { const id = await rpc<string>('create_club', { p_name: name.trim(), p_tag: tag, p_emblem: emblem, p_desc: desc.trim() || null, p_policy: policy, p_min_level: 1 }); sfx('win'); buzz('success'); toast('باشگاه ساخته شد!', 'ok'); onDone(id); }
    catch (e) { toast(errFa(e), 'err'); } finally { setBusy(false); }
  };
  return (
    <ScrollView contentContainerStyle={{ padding: S.l, paddingBottom: S.xl * 2 }} keyboardShouldPersistTaps="handled">
      <Field label="نام باشگاه" value={name} onChangeText={setName} maxLength={24} />
      <Field label="تگ (۲ تا ۵ حرف انگلیسی)" value={tag} onChangeText={v => setTag(v.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 5))} autoCapitalize="characters" style={{ textAlign: 'center', fontFamily: F.head, letterSpacing: 3 }} />
      <Field label="توضیح" value={desc} onChangeText={setDesc} maxLength={300} multiline style={{ height: 80, textAlignVertical: 'top', paddingTop: S.s }} />
      <T s="نشان" style={{ fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginBottom: S.s }} />
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', gap: S.s }}>
        {CLUB_EMBLEMS.map(e => <Press key={e} onPress={() => setEmblem(e)} style={[st.emb, e === emblem && { borderColor: C.gold, backgroundColor: 'rgba(255,210,87,.15)' }]}><Img src={discImg(e)} style={{ width: 40, height: 40 }} /></Press>)}
      </View>
      <T s="عضوگیری" style={{ fontFamily: F.bold, fontSize: TS.small, color: C.dim, textAlign: 'right', marginTop: S.l, marginBottom: S.s }} />
      <Segment value={policy} onChange={setPolicy} items={[['open', 'آزاد'], ['request', 'با درخواست'], ['invite', 'فقط دعوت']]} accent={C.gold} />
      <Btn label={busy ? '…' : 'ساخت باشگاه · ۵۰ الماس'} onPress={go} disabled={busy} colors={G.gold} style={{ marginTop: S.l }} />
    </ScrollView>
  );
}

// ======================= friends =======================
function Friends({ bottom }: { bottom: number }) {
  const { uid } = useAuth(); const nav = useNav();
  const [mode, setMode] = useState<'following' | 'followers'>('following');
  const [rows, setRows] = useState<any[] | null>(null);
  const load = useCallback(async () => {
    setRows(null);
    const col = mode === 'following' ? 'follower' : 'followee', other = mode === 'following' ? 'followee' : 'follower';
    const { data } = await supabase.from('follows').select(`${other}`).eq(col, uid!).limit(200);
    const ids = (data || []).map((r: any) => r[other]);
    if (!ids.length) { setRows([]); return; }
    const { data: ps } = await supabase.from('profiles').select('id, username, avatar, avatar_url, level, online_at, league').in('id', ids);
    setRows((ps || []).sort((a: any, b: any) => Number(isOnline(b.online_at)) - Number(isOnline(a.online_at))));
  }, [mode, uid]);
  useEffect(() => { load(); }, [load]);
  return (
    <FlatList data={rows || []} keyExtractor={r => r.id}
      ListHeaderComponent={<View style={{ paddingHorizontal: S.l, marginBottom: S.s }}><Segment value={mode} onChange={setMode} items={[['following', 'دنبال‌شده‌ها'], ['followers', 'دنبال‌کننده‌ها']]} accent={C.green} /></View>}
      renderItem={({ item }) => (
        <View style={{ paddingHorizontal: S.l }}>
          <Press onPress={() => nav.openProfile(item.id)} scaleTo={.98}>
            <View style={st.row}>
              <Avatar avatar={item.avatar} url={item.avatar_url} size={44} ring={isOnline(item.online_at) ? C.green : C.line} />
              <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
                <T s={item.username} n={1} style={{ fontFamily: F.bold }} />
                <T s={isOnline(item.online_at) ? 'آنلاین' : `آخرین بازدید ${timeAgo(item.online_at)} پیش`} style={{ fontSize: TS.cap, color: isOnline(item.online_at) ? C.green : C.dim }} />
              </View>
              <Badge label={`سطح ${fa(item.level)}`} color={C.gold} />
            </View>
          </Press>
        </View>
      )}
      ListEmptyComponent={!rows ? <View style={{ padding: S.xl }}><Spinner /></View> : <Empty img={UI2.x_player} title={mode === 'following' ? 'هنوز کسی را دنبال نمی‌کنی' : 'هنوز دنبال‌کننده‌ای نداری'} sub="از رده‌بندی یا جستجو بازیکن‌ها را پیدا کن" />}
      contentContainerStyle={{ paddingBottom: bottom + S.l }} />
  );
}

export const st = StyleSheet.create({
  row: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 60, paddingHorizontal: S.s, marginBottom: S.s, borderRadius: 16, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(10,16,44,.86)' },
  pill: { height: 44, paddingHorizontal: S.m, borderRadius: 14, borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,14,40,.85)' },
  convIcon: { width: 48, height: 48, borderRadius: 24, borderWidth: 2, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' },
  on: { position: 'absolute', bottom: 1, left: 1, width: 13, height: 13, borderRadius: 7, backgroundColor: C.green, borderWidth: 2, borderColor: '#0b1236' },
  unread: { minWidth: 22, height: 22, paddingHorizontal: 5, borderRadius: 11, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center', marginTop: 4 },
  emb: { width: 56, height: 56, borderRadius: 14, borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center' },
});
