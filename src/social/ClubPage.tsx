// Club page: emblem, tag, description, members with roles, join/request, requests management, invite, club chat, leave.
import React, { useCallback, useEffect, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Btn, Img, Panel, Press, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { errFa, rpc, supabase } from '../net/supabase';
import { useNav } from '../nav';
import { Avatar, Badge, ErrorState, Field, Header, S, Spinner, TS, discImg } from '../online/ui';
import { isOnline } from './Social';

const ROLE_FA: Record<string, [string, string]> = { leader: ['رهبر', C.gold], officer: ['افسر', C.cyan], member: ['عضو', C.dim] };

export default function ClubPage({ id, onBack, toast }: { id: string; onBack: () => void; toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets(); const { uid, profile, refreshProfile } = useAuth(); const nav = useNav();
  const [club, setClub] = useState<any>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [reqs, setReqs] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState('');
  const [inv, setInv] = useState(''); const [found, setFound] = useState<any[]>([]);
  const [sureLeave, setSureLeave] = useState(false);

  const load = useCallback(async () => {
    const [c, m, r] = await Promise.all([
      supabase.from('club_list').select('*').eq('id', id).maybeSingle(),
      supabase.from('club_members').select('user_id, role, joined_at, profiles(username, avatar, avatar_url, level, rating, online_at)').eq('club_id', id),
      supabase.from('club_requests').select('user_id, kind, message, created_at, profiles(username, avatar, avatar_url, level)').eq('club_id', id),
    ]);
    if (c.error || !c.data) { setErr(c.error ? errFa(c.error) : 'باشگاه پیدا نشد'); return; }
    setErr(null); setClub(c.data);
    const order = { leader: 0, officer: 1, member: 2 } as Record<string, number>;
    setMembers(((m.data || []) as any[]).sort((a, b) => order[a.role] - order[b.role] || (b.profiles?.rating ?? 0) - (a.profiles?.rating ?? 0)));
    setReqs((r.data || []) as any[]);
  }, [id]);
  useEffect(() => {
    load();
    const ch = supabase.channel(`club:${id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'club_members', filter: `club_id=eq.${id}` }, () => load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'club_requests', filter: `club_id=eq.${id}` }, () => load()).subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);
  useEffect(() => {
    const term = inv.trim(); if (term.length < 2) { setFound([]); return; }
    const t = setTimeout(async () => { const { data } = await supabase.from('profiles').select('id, username, avatar, avatar_url, club_id').ilike('username', `%${term.replace(/[%_]/g, '')}%`).is('club_id', null).limit(8); setFound(data || []); }, 300);
    return () => clearTimeout(t);
  }, [inv]);

  const run = async (k: string, fn: () => Promise<any>, ok?: string) => {
    if (busy) return; setBusy(k);
    try { const r = await fn(); if (ok) toast(ok, 'ok'); buzz('success'); await load(); refreshProfile(); return r; }
    catch (e) { toast(errFa(e), 'err'); buzz('heavy'); } finally { setBusy(null); }
  };
  if (err) return <View style={{ flex: 1 }}><Header title="باشگاه" onBack={onBack} /><View style={{ paddingTop: ins.top + 90 }}><ErrorState msg={err} onRetry={load} /></View></View>;
  if (!club) return <View style={{ flex: 1 }}><Header title="باشگاه" onBack={onBack} /><View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner size={36} /></View></View>;

  const mine = members.find(m => m.user_id === uid);
  const role = mine?.role as string | undefined;
  const officer = role === 'leader' || role === 'officer';
  const myReq = reqs.find(r => r.user_id === uid);
  const requests = reqs.filter(r => r.kind === 'request');
  const join = () => run('join', async () => { const r = await rpc<string>('join_club', { p_club: id, p_message: msg.trim() || null }); if (r === 'joined') { sfx('win'); toast('به باشگاه پیوستی!', 'ok'); } else toast('درخواستت ارسال شد', 'ok'); });

  return (
    <View style={{ flex: 1 }}>
      <Header title={club.name} en={`CLUB · ${club.tag}`} accent={C.gold} onBack={onBack} />
      <ScrollView contentContainerStyle={{ paddingTop: ins.top + 76, paddingHorizontal: S.l, paddingBottom: ins.bottom + S.xl }} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
        <Panel style={{ padding: S.l, alignItems: 'center' }} accent={C.gold} glow>
          <LinearGradient colors={['rgba(255,210,87,.22)', 'transparent']} style={StyleSheet.absoluteFill} />
          <Img src={discImg(club.emblem)} style={{ width: 96, height: 96 }} />
          <View style={{ flexDirection: 'row-reverse', alignItems: 'center', marginTop: S.s }}>
            <T s={club.name} style={{ fontFamily: F.title, fontSize: 20 }} /><Badge label={club.tag} color={C.gold} />
          </View>
          {club.description ? <T s={club.description} style={{ fontSize: TS.small, color: '#d9e6ff', textAlign: 'center', marginTop: S.s }} /> : null}
          <View style={{ flexDirection: 'row-reverse', alignSelf: 'stretch', marginTop: S.m }}>
            {[[`${fa(club.members)}/${fa(club.max_members)}`, 'اعضا'], [fa(club.power), 'قدرت'], [club.join_policy === 'open' ? 'آزاد' : club.join_policy === 'request' ? 'درخواست' : 'دعوت', 'عضوگیری'], [fa(club.min_level), 'حداقل سطح']].map(([v, l]) => (
              <View key={l} style={{ flex: 1, alignItems: 'center' }}><T s={v} style={{ fontFamily: F.bold, fontSize: TS.body }} /><T s={l} style={{ fontSize: TS.tiny, color: C.dim }} /></View>
            ))}
          </View>
        </Panel>

        {mine ? (
          <View style={{ flexDirection: 'row-reverse', marginTop: S.m }}>
            {club.conversation_id ? <Btn label="چت باشگاه" small colors={G.green} onPress={() => nav.openChat(club.conversation_id)} style={{ flex: 1, marginLeft: S.s }} /> : null}
            <Btn label={sureLeave ? 'مطمئنی؟' : 'ترک باشگاه'} small colors={G.red} style={{ flex: 1 }}
              onPress={() => { if (!sureLeave) { setSureLeave(true); return; } run('leave', () => rpc('leave_club'), 'از باشگاه خارج شدی').then(() => onBack()); }} />
          </View>
        ) : profile?.club_id ? (
          <T s="تو عضو باشگاه دیگری هستی" style={{ color: C.dim, textAlign: 'center', marginTop: S.m }} />
        ) : myReq?.kind === 'request' ? (
          <T s="درخواست عضویتت در انتظار بررسی است" style={{ color: C.cyan, textAlign: 'center', marginTop: S.m }} />
        ) : club.join_policy === 'invite' && myReq?.kind !== 'invite' ? (
          <T s="این باشگاه فقط با دعوت عضو می‌گیرد" style={{ color: C.dim, textAlign: 'center', marginTop: S.m }} />
        ) : (
          <View style={{ marginTop: S.m }}>
            {club.join_policy === 'request' && myReq?.kind !== 'invite' ? <Field label="پیام برای رهبر (اختیاری)" value={msg} onChangeText={setMsg} maxLength={120} /> : null}
            <Btn label={busy === 'join' ? '…' : myReq?.kind === 'invite' ? 'پذیرفتن دعوت' : club.join_policy === 'open' ? 'پیوستن' : 'ارسال درخواست'} colors={G.gold} onPress={join} disabled={!!busy} />
          </View>
        )}

        {officer && requests.length ? (
          <>
            <T s={`درخواست‌ها (${fa(requests.length)})`} style={st.h} />
            {requests.map(r => (
              <View key={r.user_id} style={st.row}>
                <Avatar avatar={r.profiles?.avatar} url={r.profiles?.avatar_url} size={40} />
                <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
                  <T s={r.profiles?.username || '…'} n={1} style={{ fontFamily: F.bold }} />
                  {r.message ? <T s={r.message} n={2} style={{ fontSize: TS.cap, color: C.dim }} /> : null}
                </View>
                <Press onPress={() => run('d' + r.user_id, () => rpc('club_decide', { p_club: id, p_user: r.user_id, p_accept: true }), 'پذیرفته شد')} style={st.sm}><T s="✓" style={{ color: C.green, fontSize: 18 }} /></Press>
                <Press onPress={() => run('d' + r.user_id, () => rpc('club_decide', { p_club: id, p_user: r.user_id, p_accept: false }))} style={st.sm}><T s="✕" style={{ color: C.red, fontSize: 16 }} /></Press>
              </View>
            ))}
          </>
        ) : null}

        {officer ? (
          <>
            <T s="دعوت بازیکن" style={st.h} />
            <Field value={inv} onChangeText={setInv} placeholder="نام کاربری…" autoCapitalize="none" />
            {found.map(f => (
              <View key={f.id} style={st.row}>
                <Avatar avatar={f.avatar} url={f.avatar_url} size={36} />
                <T s={f.username} n={1} style={{ flex: 1, marginRight: S.s, textAlign: 'right' }} />
                <Press onPress={() => { run('inv', () => rpc('club_invite', { p_club: id, p_user: f.id }), 'دعوت فرستاده شد'); setInv(''); }} style={st.sm}><T s="دعوت" style={{ color: C.gold, fontSize: TS.small }} /></Press>
              </View>
            ))}
          </>
        ) : null}

        <T s={`اعضا (${fa(members.length)})`} style={st.h} />
        {members.map(m => {
          const [rl, rc] = ROLE_FA[m.role];
          return (
            <View key={m.user_id} style={st.row}>
              <Press onPress={() => nav.openProfile(m.user_id)}><Avatar avatar={m.profiles?.avatar} url={m.profiles?.avatar_url} size={42} ring={isOnline(m.profiles?.online_at) ? C.green : C.line} /></Press>
              <View style={{ flex: 1, marginRight: S.s, alignItems: 'flex-end' }}>
                <T s={(m.profiles?.username || '…') + (m.user_id === uid ? ' (تو)' : '')} n={1} style={{ fontFamily: F.bold }} />
                <View style={{ flexDirection: 'row-reverse' }}><Badge label={rl} color={rc} /><Badge label={`سطح ${fa(m.profiles?.level ?? 1)}`} color={C.sky} /></View>
              </View>
              {role === 'leader' && m.user_id !== uid ? (
                <>
                  <Press onPress={() => run('a' + m.user_id, () => rpc('club_member_action', { p_club: id, p_user: m.user_id, p_action: m.role === 'officer' ? 'demote' : 'promote' }))} style={st.sm}><T s={m.role === 'officer' ? '⬇' : '⬆'} style={{ color: C.cyan, fontSize: 16 }} /></Press>
                  <Press onPress={() => run('a' + m.user_id, () => rpc('club_member_action', { p_club: id, p_user: m.user_id, p_action: 'transfer' }), 'رهبری منتقل شد')} style={st.sm}><T s="👑" style={{ fontSize: 14 }} /></Press>
                </>
              ) : null}
              {officer && m.user_id !== uid && (m.role === 'member' || (role === 'leader' && m.role === 'officer')) ? (
                <Press onPress={() => run('a' + m.user_id, () => rpc('club_member_action', { p_club: id, p_user: m.user_id, p_action: 'kick' }), 'اخراج شد')} style={st.sm}><T s="✕" style={{ color: C.red }} /></Press>
              ) : null}
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  h: { fontFamily: F.bold, fontSize: TS.h, textAlign: 'right', marginTop: S.l, marginBottom: S.s },
  row: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 60, paddingHorizontal: S.s, marginBottom: S.s, borderRadius: 16, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(10,16,44,.86)' },
  sm: { width: 40, height: 44, alignItems: 'center', justifyContent: 'center' },
});
