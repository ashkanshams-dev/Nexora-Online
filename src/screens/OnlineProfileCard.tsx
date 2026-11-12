// Profile tab → online section: photo upload, bio, level/XP bar, rating & league, arena, recent XP events.
import React, { memo, useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { UI, UI2 } from '../game/assets';
import { Bar, Btn, Img, Panel, Press, T, Title } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz } from '../sound';
import { useAuth } from '../net/auth';
import { errFa, levelProgress, supabase } from '../net/supabase';
import { pickAndUpload } from '../net/media';
import { useNav } from '../nav';
import { Avatar, Badge, Field, LEAGUE_IMG, S, Spinner, TS, useLeagues } from '../online/ui';
import { timeAgo } from '../social/Social';

const REASON_FA: Record<string, string> = { match: 'مسابقه‌ی آنلاین', tournament: 'جایزه‌ی تورنمنت', challenge: 'چالش روزانه', offline: 'برد مقابل ربات' };

function OnlineProfileCard({ toast }: { toast: (m: string, k?: string) => void }) {
  const { uid, profile, isGuest, ensure } = useAuth(); const nav = useNav(); const leagues = useLeagues();
  const [events, setEvents] = useState<{ id: number; amount: number; reason: string; created_at: string }[] | null>(null);
  const [up, setUp] = useState(false);
  const [bio, setBio] = useState(''); const [editBio, setEditBio] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!uid) return;
    let alive = true;
    const load = () => supabase.from('xp_events').select('id, amount, reason, created_at').eq('user_id', uid).order('created_at', { ascending: false }).limit(10)
      .then(({ data }) => { if (alive) setEvents((data || []) as any); }, () => {});
    load();
    return () => { alive = false; };
  }, [uid, profile?.xp]);

  if (!uid || !profile) {
    return (
      <Panel style={{ marginHorizontal: S.l, padding: S.m, flexDirection: 'row-reverse', alignItems: 'center' }} accent={C.cyan}>
        <Img src={UI.portal_globe} style={{ width: 56, height: 56 }} />
        <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
          <T s="پروفایل آنلاین" style={{ fontFamily: F.bold, fontSize: TS.h }} />
          <T s="سطح، لیگ و آمار آنلاین بعد از ورود نمایش داده می‌شود" style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right' }} />
        </View>
        <Btn label={busy ? '…' : 'ورود'} small onPress={async () => { setBusy(true); try { await ensure(); } catch { toast('اتصال برقرار نشد', 'err'); } finally { setBusy(false); } }} />
      </Panel>
    );
  }
  const lp = levelProgress(profile.xp);
  const list = (leagues || []).slice().sort((a, b) => a.sort - b.sort);
  const cur = list.filter(l => l.min_rating <= profile.rating).pop(), nxt = list.find(l => l.min_rating > profile.rating);
  const played = profile.wins + profile.losses + profile.draws;

  const upload = async () => {
    setUp(true);
    const r = await pickAndUpload('avatars', uid, { size: 512, square: true });
    if (r.ok) {
      const { error } = await supabase.from('profiles').update({ avatar_url: r.url }).eq('id', uid);
      if (error) toast(errFa(error), 'err'); else { toast('عکس پروفایل به‌روز شد', 'ok'); buzz('success'); }
    } else if (!r.cancelled) toast(r.error, 'err');
    setUp(false);
  };
  const removePhoto = async () => { await supabase.from('profiles').update({ avatar_url: null }).eq('id', uid); toast('عکس حذف شد؛ دیسک فعال نمایش داده می‌شود', 'ok'); };
  const saveBio = async () => {
    const { error } = await supabase.from('profiles').update({ bio: bio.trim().slice(0, 160) || null }).eq('id', uid);
    if (error) toast(errFa(error), 'err'); else { setEditBio(false); toast('ذخیره شد', 'ok'); }
  };

  return (
    <View>
      <Panel style={{ marginHorizontal: S.l, padding: S.m }} accent={cur?.color || C.cyan} glow>
        <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
          <Press onPress={upload} disabled={up}>
            <Avatar avatar={profile.equipped_disc} url={profile.avatar_url} size={76} ring={cur?.color || C.cyan} />
            <View style={st.cam}>{up ? <Spinner /> : <T s="📷" style={{ fontSize: 13 }} />}</View>
          </Press>
          <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
            <T s={profile.username} n={1} style={{ fontFamily: F.title, fontSize: 18 }} />
            <View style={{ flexDirection: 'row-reverse', marginTop: S.xs, flexWrap: 'wrap', rowGap: 4 }}>
              <Badge label={`سطح ${fa(lp.level)}`} color={C.gold} />
              {cur ? <Badge label={cur.name_fa} color={cur.color} /> : null}
              {isGuest ? <Badge label="مهمان" color={C.dim} /> : null}
            </View>
            {profile.avatar_url ? <Press onPress={removePhoto} style={{ minHeight: 32, justifyContent: 'center' }}><T s="حذف عکس" style={{ fontSize: TS.tiny, color: C.dim }} /></Press> : null}
          </View>
        </View>
        {editBio ? (
          <View style={{ marginTop: S.m }}>
            <Field value={bio} onChangeText={setBio} maxLength={160} placeholder="چند کلمه درباره‌ی خودت…" multiline style={{ height: 72, textAlignVertical: 'top', paddingTop: S.s }} />
            <View style={{ flexDirection: 'row-reverse' }}>
              <Btn label="ذخیره" small onPress={saveBio} style={{ flex: 1, marginLeft: S.s }} /><Btn label="انصراف" small colors={G.dark} onPress={() => setEditBio(false)} style={{ flex: 1 }} />
            </View>
          </View>
        ) : (
          <Press onPress={() => { setBio(profile.bio || ''); setEditBio(true); }} style={{ marginTop: S.s, minHeight: 44, justifyContent: 'center' }}>
            <T s={profile.bio || '✎ افزودن بیو'} style={{ fontSize: TS.small, color: profile.bio ? '#d6e6ff' : C.cyan, textAlign: 'right' }} />
          </Press>
        )}
        <View style={{ marginTop: S.s }}><Bar v={lp.frac} color={C.cyan} color2={C.violet} h={10} /></View>
        <T s={`${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}`} style={{ fontSize: TS.tiny, color: C.dim, textAlign: 'center', marginTop: S.xs }} />
        <View style={{ flexDirection: 'row-reverse', marginTop: S.m }}>
          {[[fa(profile.rating), 'امتیاز'], [fa(profile.arena_points), 'آرنا'], [`🔥${fa(profile.win_streak)}`, 'برد پیاپی'], [fa(played), 'بازی آنلاین']].map(([v, l]) => (
            <View key={l} style={{ flex: 1, alignItems: 'center' }}><T s={v} style={{ fontFamily: F.title, fontSize: 15 }} /><T s={l} style={{ fontSize: TS.tiny, color: C.dim }} /></View>
          ))}
        </View>
      </Panel>

      {cur ? (
        <Press onPress={() => nav.openOnline('leagues')} scaleTo={.98} style={{ marginHorizontal: S.l, marginTop: S.s }}>
          <Panel style={{ padding: S.m, flexDirection: 'row-reverse', alignItems: 'center' }} accent={cur.color}>
            <Img src={(UI as any)[LEAGUE_IMG[cur.id]]} style={{ width: 52, height: 52 }} />
            <View style={{ flex: 1, marginRight: S.m }}>
              <T s={`لیگ ${cur.name_fa}`} style={{ fontFamily: F.bold, fontSize: TS.body, textAlign: 'right', color: cur.color }} />
              <View style={{ marginTop: S.xs }}><Bar v={nxt ? (profile.rating - cur.min_rating) / (nxt.min_rating - cur.min_rating) : 1} color={cur.color} color2={C.indigo} h={6} /></View>
              <T s={nxt ? `${fa(nxt.min_rating - profile.rating)} امتیاز تا ${nxt.name_fa}` : 'بالاترین لیگ!'} style={{ fontSize: TS.tiny, color: C.dim, textAlign: 'right', marginTop: 2 }} />
            </View>
          </Panel>
        </Press>
      ) : null}

      <Title s="تاریخچه‌ی XP" en="RECENT XP" accent={C.cyan} />
      <View style={{ paddingHorizontal: S.l }}>
        {!events ? <Spinner /> : !events.length ? <T s="هنوز XP آنلاینی نگرفتی؛ یک مسابقه‌ی سریع بزن!" style={{ color: C.dim, textAlign: 'center', fontSize: TS.small }} /> : events.map(e => (
          <View key={e.id} style={st.ev}>
            <Img src={e.reason === 'tournament' ? UI2.x_trophy : e.reason === 'challenge' ? UI2.c_calendar : UI2.x_star} style={{ width: 28, height: 28 }} />
            <T s={REASON_FA[e.reason] || e.reason} style={{ flex: 1, marginRight: S.s, fontSize: TS.small, textAlign: 'right' }} />
            <T s={timeAgo(e.created_at)} style={{ fontSize: TS.tiny, color: C.dim, marginLeft: S.s }} />
            <T s={`${e.amount >= 0 ? '+' : ''}${fa(e.amount)} XP`} style={{ fontFamily: F.bold, fontSize: TS.small, color: e.amount >= 0 ? C.green : C.red, minWidth: 64, textAlign: 'left' }} />
          </View>
        ))}
      </View>
    </View>
  );
}
export default memo(OnlineProfileCard);

const st = StyleSheet.create({
  cam: { position: 'absolute', bottom: -2, left: -2, width: 28, height: 28, borderRadius: 14, backgroundColor: '#0e1640', borderWidth: 1, borderColor: C.cyan, alignItems: 'center', justifyContent: 'center' },
  ev: { flexDirection: 'row-reverse', alignItems: 'center', minHeight: 44, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,.08)' },
});
