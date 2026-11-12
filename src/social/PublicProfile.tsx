// Public profile of any player: avatar/photo, level, league, stats, followers, follow/unfollow, message, block, club.
import React, { useCallback, useEffect, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI, UI2 } from '../game/assets';
import { Bar, Btn, Img, Panel, Press, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { OnlineProfile, errFa, levelProgress, rpc, supabase } from '../net/supabase';
import { discStats } from '../net/discs';
import { useNav } from '../nav';
import { Avatar, Badge, ErrorState, Header, LEAGUE_IMG, S, Spinner, StatBars, TS, discImg, useLeagues } from '../online/ui';
import { isOnline, timeAgo } from './Social';

export default function PublicProfile({ id, onBack, toast }: { id: string; onBack: () => void; toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets(); const { uid } = useAuth(); const nav = useNav(); const leagues = useLeagues();
  const [p, setP] = useState<OnlineProfile | null>(null);
  const [stats, setStats] = useState<{ followers: number; following: number } | null>(null);
  const [club, setClub] = useState<any>(null);
  const [following, setFollowing] = useState(false);
  const [blocked, setBlocked] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const { data, error } = await supabase.from('profiles').select('*').eq('id', id).maybeSingle();
    if (error || !data) { setErr(error ? errFa(error) : 'بازیکن پیدا نشد'); return; }
    setP(data as OnlineProfile); setErr(null);
    const [s, f, b, c] = await Promise.all([
      supabase.from('profile_stats').select('*').eq('id', id).maybeSingle(),
      uid ? supabase.from('follows').select('followee').eq('follower', uid).eq('followee', id).maybeSingle() : Promise.resolve({ data: null } as any),
      uid ? supabase.from('user_blocks').select('blocked').eq('blocker', uid).eq('blocked', id).maybeSingle() : Promise.resolve({ data: null } as any),
      (data as any).club_id ? supabase.from('clubs').select('id, name, tag, emblem').eq('id', (data as any).club_id).maybeSingle() : Promise.resolve({ data: null } as any),
    ]);
    setStats(s.data as any); setFollowing(!!f.data); setBlocked(!!b.data); setClub(c.data);
  }, [id, uid]);
  useEffect(() => { load(); }, [load]);

  const toggleFollow = async () => {
    if (!uid || busy) return; setBusy(true);
    const r = following ? await supabase.from('follows').delete().eq('follower', uid).eq('followee', id) : await supabase.from('follows').insert({ follower: uid, followee: id });
    setBusy(false);
    if (r.error) { toast(errFa(r.error), 'err'); return; }
    setFollowing(!following); setStats(s => s && { ...s, followers: s.followers + (following ? -1 : 1) }); buzz('medium'); if (!following) sfx('ready');
  };
  const message = async () => { try { const cid = await rpc<string>('open_dm', { p_user: id }); nav.openChat(cid); } catch (e) { toast(errFa(e), 'err'); } };
  const toggleBlock = async () => {
    if (!uid) return;
    const r = blocked ? await supabase.from('user_blocks').delete().eq('blocker', uid).eq('blocked', id) : await supabase.from('user_blocks').insert({ blocker: uid, blocked: id });
    if (r.error) { toast(errFa(r.error), 'err'); return; } setBlocked(!blocked); toast(blocked ? 'از مسدودی خارج شد' : 'کاربر مسدود شد', 'ok');
  };

  if (err) return <View style={{ flex: 1 }}><Header title="پروفایل" onBack={onBack} /><View style={{ paddingTop: ins.top + 90 }}><ErrorState msg={err} onRetry={load} /></View></View>;
  if (!p) return <View style={{ flex: 1 }}><Header title="پروفایل" onBack={onBack} /><View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner size={36} /></View></View>;
  const lp = levelProgress(p.xp), lg = leagues?.find(l => l.id === p.league);
  const played = p.wins + p.losses + p.draws, wr = played ? Math.round(p.wins / played * 100) : 0;
  const ds = discStats(p.equipped_disc);
  const me = uid === id;
  return (
    <View style={{ flex: 1 }}>
      <Header title={p.username} en="PILOT PROFILE" onBack={onBack} />
      <ScrollView contentContainerStyle={{ paddingTop: ins.top + 76, paddingHorizontal: S.l, paddingBottom: ins.bottom + S.xl }} showsVerticalScrollIndicator={false}>
        <Panel style={{ padding: S.l, alignItems: 'center' }} accent={lg?.color || C.cyan} glow>
          <LinearGradient colors={[(lg?.color || C.cyan) + '33', 'transparent']} style={StyleSheet.absoluteFill} />
          <View>
            <Avatar avatar={p.equipped_disc || p.avatar} url={p.avatar_url} size={104} ring={lg?.color || C.cyan} />
            {isOnline(p.online_at) ? <View style={st.on} /> : null}
          </View>
          <T s={p.username} style={{ fontFamily: F.title, fontSize: 20, marginTop: S.s }} />
          <T s={isOnline(p.online_at) ? 'آنلاین' : `آخرین بازدید ${timeAgo(p.online_at)} پیش`} style={{ fontSize: TS.cap, color: isOnline(p.online_at) ? C.green : C.dim }} />
          {p.bio ? <T s={p.bio} style={{ fontSize: TS.small, color: '#cfe0ff', textAlign: 'center', marginTop: S.s }} /> : null}
          <View style={{ flexDirection: 'row-reverse', marginTop: S.s, flexWrap: 'wrap', justifyContent: 'center', rowGap: 4 }}>
            <Badge label={`سطح ${fa(p.level)}`} color={C.gold} />
            {lg ? <Badge label={`لیگ ${lg.name_fa}`} color={lg.color} /> : null}
            {p.is_guest ? <Badge label="مهمان" color={C.dim} /> : null}
            {club ? <Badge label={`[${club.tag}] ${club.name}`} color={C.orange} /> : null}
          </View>
          <View style={{ alignSelf: 'stretch', marginTop: S.m }}><Bar v={lp.frac} color={C.cyan} color2={C.violet} h={8} /></View>
          <T s={`${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}`} style={{ fontSize: TS.tiny, color: C.dim, marginTop: S.xs }} />
          <View style={{ flexDirection: 'row-reverse', alignSelf: 'stretch', marginTop: S.m }}>
            {[[stats?.followers ?? 0, 'دنبال‌کننده'], [stats?.following ?? 0, 'دنبال‌شده'], [p.trophies, 'جام']].map(([v, l]) => (
              <View key={l as string} style={{ flex: 1, alignItems: 'center' }}><T s={fa(v as number)} style={{ fontFamily: F.title, fontSize: 18 }} /><T s={l as string} style={{ fontSize: TS.tiny, color: C.dim }} /></View>
            ))}
          </View>
          {!me ? (
            <View style={{ flexDirection: 'row-reverse', alignSelf: 'stretch', marginTop: S.m }}>
              <Btn label={following ? 'دنبال می‌کنی ✓' : 'دنبال کردن'} small colors={following ? G.dark : G.primary} onPress={toggleFollow} disabled={busy} style={{ flex: 1, marginLeft: S.s }} />
              <Btn label="پیام" small colors={G.green} onPress={message} style={{ flex: 1 }} />
            </View>
          ) : null}
        </Panel>

        <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', marginTop: S.m, marginHorizontal: -S.xs }}>
          {([[UI2.x_ball, 'بازی', played], [UI2.x_medal, 'برد', p.wins], [UI2.x_shield, 'باخت', p.losses], [UI2.x_star, 'درصد برد', `${fa(wr)}٪`], [UI2.x_statue, 'گل', p.goals], [UI2.x_crown, 'آرنا', p.arena_points]] as const).map(([img, k, v]) => (
            <View key={k} style={{ width: '33.33%', padding: S.xs }}>
              <Panel style={{ alignItems: 'center', paddingVertical: S.s }} accent="transparent">
                <Img src={img} style={{ width: 34, height: 34 }} />
                <T s={typeof v === 'number' ? fa(v) : v} style={{ fontFamily: F.title, fontSize: 16, marginTop: 2 }} />
                <T s={k} style={{ fontSize: TS.tiny, color: C.dim }} />
              </Panel>
            </View>
          ))}
        </View>

        <Panel style={{ padding: S.m, marginTop: S.s, flexDirection: 'row-reverse', alignItems: 'center' }} accent="transparent">
          <Img src={discImg(p.equipped_disc)} style={{ width: 56, height: 56 }} />
          <View style={{ flex: 1, marginRight: S.m }}>
            <T s="دیسک فعال" style={{ fontFamily: F.bold, fontSize: TS.small, textAlign: 'right' }} />
            <StatBars power={ds.power} accuracy={ds.accuracy} />
          </View>
          {lg ? <Img src={(UI as any)[LEAGUE_IMG[lg.id]]} style={{ width: 48, height: 48, marginRight: S.s }} /> : null}
        </Panel>
        {club ? <Btn label={`باشگاه ${club.name}`} small colors={G.gold} onPress={() => nav.openClub(club.id)} style={{ marginTop: S.m }} /> : null}
        {!me ? <Press onPress={toggleBlock} style={{ marginTop: S.m, minHeight: 44, justifyContent: 'center' }}><T s={blocked ? 'رفع مسدودی' : 'مسدود کردن این کاربر'} style={{ color: C.red, textAlign: 'center', fontSize: TS.small }} /></Press> : null}
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  on: { position: 'absolute', bottom: 6, left: 6, width: 18, height: 18, borderRadius: 9, backgroundColor: C.green, borderWidth: 3, borderColor: '#0b1236' },
});
