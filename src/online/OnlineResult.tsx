// Online result: score, XP / coins / rating actually granted by the backend (profile diff), level-up.
import React, { useEffect, useState } from 'react';
import { ScrollView, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSpring, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TEAM_IMG, UI, UI2 } from '../game/assets';
import { teamKey } from '../game/util';
import { Bar, Btn, Img, Panel, Pulse, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { OnlineProfile, levelProgress } from '../net/supabase';
import type { OnlineOutcome } from './OnlineMatch';
import { S, Spinner, TS } from './ui';
import { oracleImg, resultLine } from '../oracle/Oracle';
import { Float } from '../ui/kit';

export default function OnlineResult({ o, before, onLobby, onLeave }: { o: OnlineOutcome; before: OnlineProfile | null; onLobby: () => void; onLeave: () => void }) {
  const { width: W } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const { refreshProfile } = useAuth();
  const [after, setAfter] = useState<OnlineProfile | null>(null);
  const mine = o.myTeam;
  const out = mine === null ? 'draw' : o.winner === -1 ? 'draw' : o.winner === mine ? 'victory' : 'defeat';
  const sc = useSharedValue(0), rays = useSharedValue(0);
  useEffect(() => {
    sc.value = withSpring(1, { damping: 9, stiffness: 120 });
    rays.value = withRepeat(withTiming(1, { duration: 20000, easing: Easing.linear }), -1, false);
    if (mine !== null) { if (out === 'victory') { sfx('win'); buzz('success'); } else if (out === 'defeat') sfx('lose'); }
    let alive = true;
    // the backend has granted rewards by now; poll the profile a couple of times in case realtime is late
    const tryLoad = async (n: number) => { const p = await refreshProfile(); if (!alive) return; if (p && (!before || p.xp !== before.xp || n >= 2)) setAfter(p); else if (n < 2) setTimeout(() => tryLoad(n + 1), 1200); else setAfter(p); };
    if (mine !== null && o.reported) tryLoad(0);
    return () => { alive = false; };
  }, []);
  const banner = useAnimatedStyle(() => ({ opacity: Math.min(1, sc.value * 1.4), transform: [{ scale: .4 + sc.value * .6 }] }));
  const ray = useAnimatedStyle(() => ({ transform: [{ rotate: `${rays.value * 360}deg` }] }));
  const col = out === 'victory' ? C.gold : out === 'defeat' ? C.red : C.cyan;
  const bw = Math.min(W * .9, 380);
  const dXp = after && before ? after.xp - before.xp : null, dCoins = after && before ? after.coins - before.coins : null;
  const dRating = after && before ? after.rating - before.rating : o.ratingDelta;
  const dArena = after && before ? after.arena_points - before.arena_points : null;
  const lvUp = after && before && after.level > before.level ? after.level : null;
  const lp = after ? levelProgress(after.xp) : null;
  const line = React.useMemo(() => resultLine(out), [out]);

  return (
    <ScrollView contentContainerStyle={{ alignItems: 'center', paddingTop: ins.top + S.s, paddingBottom: ins.bottom + S.xl, paddingHorizontal: S.l }} showsVerticalScrollIndicator={false}>
      <View style={{ width: bw, height: bw * .62, alignItems: 'center', justifyContent: 'center' }}>
        <Animated.View style={[{ position: 'absolute' }, ray]}><Img src={UI2.ring} style={{ width: bw * .9, height: bw * .9, opacity: .5 }} /></Animated.View>
        <Pulse size={bw * .5} color={col + '44'} />
        <Animated.View style={banner}><Img src={UI[out]} style={{ width: bw, height: bw * .6 }} /></Animated.View>
      </View>

      <Panel style={{ flexDirection: 'row', alignItems: 'center', padding: S.m, alignSelf: 'stretch' }} accent={col} glow>
        <Side img={TEAM_IMG[teamKey(o.teams[0])]} name={o.names[0]} c={C.cyan} />
        <View style={{ alignItems: 'center' }}>
          <T s={`${o.score[0]} : ${o.score[1]}`} style={{ fontFamily: F.title, fontSize: 38, textShadowColor: col, textShadowRadius: 16 }} />
          <T s={o.ranked ? 'RANKED' : 'FRIENDLY'} style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: C.dim }} />
        </View>
        <Side img={TEAM_IMG[teamKey(o.teams[1])]} name={o.names[1]} c={C.red} />
      </Panel>

      {mine === null ? (
        <T s="تو تماشاگر این بازی بودی" style={{ color: C.dim, fontSize: TS.small, marginTop: S.m }} />
      ) : !o.reported ? (
        <Panel style={{ alignSelf: 'stretch', padding: S.m, marginTop: S.m }} accent={C.orange}>
          <T s="نتیجه روی سرور ثبت نشد؛ جایزه‌ای اعمال نشد." style={{ fontSize: TS.small, color: C.orange, textAlign: 'center' }} />
        </Panel>
      ) : !after ? (
        <View style={{ height: 120, justifyContent: 'center' }}><Spinner /><T s="در حال دریافت جوایز…" style={{ fontSize: TS.cap, color: C.dim, marginTop: S.s }} /></View>
      ) : (
        <>
          <View style={{ flexDirection: 'row-reverse', marginTop: S.m, alignSelf: 'stretch' }}>
            <Rw img={UI2.x_star} v={dXp ?? 0} c={C.cyan} d={150} label="XP" />
            <Rw img={UI2.c_coin} v={dCoins ?? 0} c={C.gold} d={300} />
            <Rw img={UI2.x_trophy} v={dRating ?? 0} c={(dRating ?? 0) >= 0 ? C.green : C.red} d={450} label="امتیاز" />
            {dArena ? <Rw img={UI2.x_crown} v={dArena} c={C.violet} d={600} label="آرنا" /> : null}
          </View>
          {lp ? (
            <Panel style={{ alignSelf: 'stretch', padding: S.m, marginTop: S.s }} accent="transparent">
              <View style={{ flexDirection: 'row-reverse', justifyContent: 'space-between' }}>
                <T s={`سطح ${fa(lp.level)}`} style={{ fontFamily: F.bold, fontSize: TS.body }} />
                <T s={`${fa(lp.cur)} / ${fa(lp.need)} XP`} style={{ fontSize: TS.cap, color: C.dim }} />
              </View>
              <View style={{ marginTop: S.s }}><Bar v={lp.frac} color={C.cyan} color2={C.violet} h={8} /></View>
            </Panel>
          ) : null}
          {lvUp ? (
            <Panel style={{ marginTop: S.s, alignSelf: 'stretch', flexDirection: 'row-reverse', alignItems: 'center', padding: S.m }} accent={C.violet} glow>
              <Img src={UI2.x_crown} style={{ width: 48, height: 48 }} />
              <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
                <T s={`سطح ${fa(lvUp)}!`} style={{ fontFamily: F.title, fontSize: 18, color: '#d6b8ff' }} />
                <T s="به سطح جدید رسیدی" style={{ fontSize: TS.cap, color: C.dim }} />
              </View>
            </Panel>
          ) : null}
        </>
      )}

      {mine !== null ? (
        <View style={{ flexDirection: 'row-reverse', alignItems: 'flex-end', alignSelf: 'stretch', marginTop: S.m }}>
          <Float amp={4}><Img src={oracleImg(line.mood)} style={{ width: 84, height: 92 }} /></Float>
          <View style={{ flex: 1, marginRight: S.s, marginBottom: S.l, padding: S.m, borderRadius: 16, borderBottomRightRadius: 4, backgroundColor: 'rgba(14,24,64,.92)', borderWidth: 1, borderColor: 'rgba(92,225,255,.4)' }}>
            <T s={line.text} style={{ fontSize: TS.small, lineHeight: 20, textAlign: 'right' }} />
          </View>
        </View>
      ) : null}

      <View style={{ alignSelf: 'stretch', marginTop: S.l }}>
        <Btn label="بازگشت به لابی" onPress={onLobby} colors={out === 'victory' ? G.gold : G.primary} />
        <View style={{ height: S.s }} />
        <Btn label="خروج از اتاق" small onPress={onLeave} colors={G.dark} />
      </View>
    </ScrollView>
  );
}

const Side = ({ img, name, c }: { img: any; name: string; c: string }) => (
  <View style={{ flex: 1, alignItems: 'center' }}>
    <View style={{ width: 54, height: 54, borderRadius: 27, borderWidth: 2, borderColor: c, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' }}><Img src={img} style={{ width: 48, height: 48, borderRadius: 24 }} /></View>
    <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: TS.small, marginTop: S.xs, maxWidth: 110 }} />
  </View>
);

function Rw({ img, v, c, d, label }: { img: any; v: number; c: string; d: number; label?: string }) {
  const [n, setN] = useState(0);
  const sc = useSharedValue(0);
  useEffect(() => {
    sc.value = withDelay(d, withSpring(1, { damping: 10 }));
    let k = 0, id: ReturnType<typeof setInterval> | null = null; const steps = 20;
    const t0 = setTimeout(() => { id = setInterval(() => { k++; setN(Math.round(v * k / steps)); if (k >= steps && id) { clearInterval(id); id = null; } }, 30); }, d);
    return () => { clearTimeout(t0); if (id) clearInterval(id); };
  }, [v]);
  const a = useAnimatedStyle(() => ({ opacity: sc.value, transform: [{ scale: .5 + sc.value * .5 }] }));
  return (
    <Animated.View style={[{ flex: 1, padding: S.xs }, a]}>
      <Panel style={{ alignItems: 'center', paddingVertical: S.s }} accent={c}>
        <Img src={img} style={{ width: 36, height: 36 }} />
        <T s={`${n >= 0 ? '+' : ''}${fa(n)}`} style={{ fontFamily: F.title, fontSize: 15, color: c, marginTop: 2 }} />
        {label ? <T s={label} style={{ fontSize: TS.tiny, color: C.dim }} /> : null}
      </Panel>
    </Animated.View>
  );
}
