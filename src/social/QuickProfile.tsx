// Tap-on-any-player card: avatar, level, followers + one-tap Follow / Message / full profile.
import React, { useEffect, useState } from 'react';
import { View } from 'react-native';
import { Btn, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { OnlineProfile, errFa, levelProgress, rpc, supabase } from '../net/supabase';
import { Avatar, Spinner } from '../online/ui';
import { isOnline } from './Social';

export default function QuickProfile({ id, onClose, onFull, onChat, toast }: { id: string; onClose: () => void; onFull: () => void; onChat: (cid: string) => void; toast: (m: string, k?: string) => void }) {
  const { uid } = useAuth();
  const [p, setP] = useState<OnlineProfile | null>(null);
  const [followers, setFollowers] = useState<number | null>(null);
  const [following, setFollowing] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    (async () => {
      const [a, s, f] = await Promise.all([
        supabase.from('profiles').select('*').eq('id', id).maybeSingle(),
        supabase.from('profile_stats').select('followers').eq('id', id).maybeSingle(),
        uid ? supabase.from('follows').select('followee').eq('follower', uid).eq('followee', id).maybeSingle() : Promise.resolve({ data: null } as any),
      ]);
      if (!alive) return;
      if (a.error || !a.data) { toast(a.error ? errFa(a.error) : 'بازیکن پیدا نشد', 'err'); onClose(); return; }
      setP(a.data as OnlineProfile); setFollowers((s.data as any)?.followers ?? 0); setFollowing(!!f.data);
    })();
    return () => { alive = false; };
  }, [id, uid]);

  const me = uid === id;
  const toggle = async () => {
    if (!uid) { toast('برای دنبال کردن وارد حساب شو', 'err'); return; }
    if (busy) return; setBusy(true);
    const r = following ? await supabase.from('follows').delete().eq('follower', uid).eq('followee', id) : await supabase.from('follows').insert({ follower: uid, followee: id });
    setBusy(false);
    if (r.error) { toast(errFa(r.error), 'err'); return; }
    setFollowing(!following); setFollowers(n => (n ?? 0) + (following ? -1 : 1)); buzz('medium');
    if (!following) { sfx('ready'); toast('دنبال کردی ✓', 'ok'); }
  };
  const message = async () => { try { const cid = await rpc<string>('open_dm', { p_user: id }); onClose(); onChat(cid); } catch (e) { toast(errFa(e), 'err'); } };

  if (!p) return <View style={{ height: 220, alignItems: 'center', justifyContent: 'center' }}><Spinner size={32} /></View>;
  const lp = levelProgress(p.xp);
  return (
    <View style={{ padding: 18, alignItems: 'center' }}>
      <Avatar avatar={p.equipped_disc || p.avatar} url={p.avatar_url} size={84} ring={isOnline((p as any).online_at) ? C.green : C.cyan} />
      <T s={p.username || '—'} style={{ fontFamily: F.bold, fontSize: 19, marginTop: 10 }} n={1} />
      <View style={{ flexDirection: 'row-reverse', marginTop: 8 }}>
        {[[fa(lp.level), 'سطح'], [fa(followers ?? 0), 'دنبال‌کننده'], [fa(p.trophies || 0), 'جام']].map(([v, l]) => (
          <View key={l} style={{ alignItems: 'center', marginHorizontal: 14 }}>
            <T s={v} style={{ fontFamily: F.bold, fontSize: 16, color: C.gold }} />
            <T s={l} style={{ fontSize: 11, color: C.dim }} />
          </View>
        ))}
      </View>
      {!me ? (
        <View style={{ flexDirection: 'row-reverse', marginTop: 16, alignSelf: 'stretch' }}>
          <Btn label={following ? 'دنبال می‌کنی ✓' : 'دنبال کردن'} small colors={following ? G.dark : G.primary} onPress={toggle} disabled={busy} style={{ flex: 1, marginLeft: 8 }} />
          <Btn label="پیام" small colors={G.violet} onPress={message} style={{ flex: 1 }} />
        </View>
      ) : null}
      <Btn label="مشاهده‌ی پروفایل کامل" small colors={G.dark} onPress={() => { onClose(); onFull(); }} style={{ alignSelf: 'stretch', marginTop: 8 }} />
    </View>
  );
}
