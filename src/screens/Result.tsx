import React, { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSpring, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TEAM_IMG, UI, UI2 } from '../game/assets';
import { teamKey } from '../game/util';
import { Btn, Float, Img, Panel, Pulse, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import type { MatchResult } from './Match';
import { oracleImg, resultLine } from '../oracle/Oracle';

export type Reward = { coins: number; xp: number; trophies: number; gems: number };

export default function Result({ r, reward, names, onAgain, onHome, cup, levelUp }: { r: MatchResult; reward: Reward | null; names: [string, string]; onAgain: () => void; onHome: () => void; cup?: { stage: number; won: boolean; champion: boolean }; levelUp?: number }) {
  const { width: W } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const [a, b] = r.score; const out = a > b ? 'victory' : a < b ? 'defeat' : 'draw';
  const line = React.useMemo(() => resultLine(out), [out]);
  const sc = useSharedValue(0), rays = useSharedValue(0);
  useEffect(() => {
    sc.value = withSpring(1, { damping: 9, stiffness: 120 });
    rays.value = withRepeat(withTiming(1, { duration: 20000, easing: Easing.linear }), -1, false);
  }, []);
  const banner = useAnimatedStyle(() => ({ opacity: Math.min(1, sc.value * 1.4), transform: [{ scale: .4 + sc.value * .6 }] }));
  const ray = useAnimatedStyle(() => ({ transform: [{ rotate: `${rays.value * 360}deg` }] }));
  const col = out === 'victory' ? C.gold : out === 'defeat' ? C.red : C.cyan;
  const bw = Math.min(W * .9, 380);
  return (
    <ScrollView contentContainerStyle={{ alignItems: 'center', paddingTop: ins.top + 10, paddingBottom: ins.bottom + 24, paddingHorizontal: 16 }} showsVerticalScrollIndicator={false}>
      <View style={{ width: bw, height: bw * .66, alignItems: 'center', justifyContent: 'center' }}>
        <Animated.View style={[{ position: 'absolute' }, ray]}><Img src={UI2.ring} style={{ width: bw * .95, height: bw * .95, opacity: .5 }} /></Animated.View>
        <Pulse size={bw * .5} color={col + '44'} />
        <Animated.View style={banner}><Img src={UI[out]} style={{ width: bw, height: bw * .62 }} /></Animated.View>
      </View>

      <Panel style={{ flexDirection: 'row', alignItems: 'center', padding: 14, alignSelf: 'stretch' }} accent={col} glow>
        <Side img={TEAM_IMG[teamKey(r.teams[0])]} name={names[0]} c={C.cyan} />
        <View style={{ alignItems: 'center' }}>
          <T s={`${a} : ${b}`} style={{ fontFamily: F.title, fontSize: 40, textShadowColor: col, textShadowRadius: 16 }} />
          <T s="FINAL" style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 4, color: C.dim }} />
        </View>
        <Side img={TEAM_IMG[teamKey(r.teams[1])]} name={names[1]} c={C.red} />
      </Panel>

      {reward ? (
        <View style={{ flexDirection: 'row-reverse', marginTop: 12, alignSelf: 'stretch' }}>
          <Rw img={UI2.c_coin} v={reward.coins} c={C.gold} d={200} />
          <Rw img={UI2.x_star} v={reward.xp} c={C.cyan} d={350} label="XP" />
          <Rw img={UI2.x_trophy} v={reward.trophies} c={reward.trophies >= 0 ? C.green : C.red} d={500} sign />
          {reward.gems ? <Rw img={UI2.x_gem} v={reward.gems} c="#9fd8ff" d={650} /> : null}
        </View>
      ) : null}

      {levelUp ? (
        <Panel style={{ marginTop: 12, alignSelf: 'stretch', flexDirection: 'row-reverse', alignItems: 'center', padding: 12 }} accent={C.violet} glow>
          <Img src={UI2.x_crown} style={{ width: 50, height: 50 }} />
          <View style={{ flex: 1, marginHorizontal: 10, alignItems: 'flex-end' }}>
            <T s={`سطح ${fa(levelUp)}!`} style={{ fontFamily: F.title, fontSize: 18, color: '#d6b8ff' }} />
            <T s="به سطح جدید رسیدی · ۱۰۰+ سکه هدیه" style={{ fontSize: 11, color: C.dim }} />
          </View>
        </Panel>
      ) : null}

      <View style={{ flexDirection: 'row-reverse', alignItems: 'flex-end', alignSelf: 'stretch', marginTop: 14 }}>
        <Float amp={4}><Img src={oracleImg(line.mood)} style={{ width: 96, height: 104 }} /></Float>
        <View style={s.say}><T s={line.text} style={{ fontSize: 12, lineHeight: 20, color: '#e6f4ff', textAlign: 'right' }} /></View>
      </View>

      {cup ? <T s={cup.champion ? 'قهرمان جام نکسورا! ۴۰۰+ سکه' : cup.won ? `مرحله‌ی ${['یک', 'دو', 'سه'][cup.stage]} از سه رد شد` : 'از جام حذف شدی'} style={{ fontFamily: F.title, fontSize: 16, textAlign: 'center', color: cup.won ? C.gold : C.red, marginTop: 14 }} /> : null}
      <View style={{ alignSelf: 'stretch', marginTop: 14 }}>
        <Btn label={cup ? (cup.won && !cup.champion ? 'مرحله‌ی بعد' : 'جام دوباره') : 'بازی دوباره'} onPress={onAgain} colors={out === 'victory' ? G.gold : G.primary} />
        <View style={{ height: 10 }} />
        <Btn label="بازگشت به خانه" small onPress={onHome} colors={G.dark} />
      </View>
    </ScrollView>
  );
}

const Side = ({ img, name, c }: { img: any; name: string; c: string }) => (
  <View style={{ flex: 1, alignItems: 'center' }}>
    <View style={{ width: 58, height: 58, borderRadius: 29, borderWidth: 2, borderColor: c, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' }}><Img src={img} style={{ width: 52, height: 52, borderRadius: 26 }} /></View>
    <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: 12, marginTop: 4 }} />
  </View>
);

function Rw({ img, v, c, d, sign, label }: { img: any; v: number; c: string; d: number; sign?: boolean; label?: string }) {
  const [n, setN] = useState(0);
  const sc = useSharedValue(0);
  useEffect(() => {
    sc.value = withDelay(d, withSpring(1, { damping: 10 }));
    let k = 0, id: ReturnType<typeof setInterval> | null = null; const steps = 20;
    const t0 = setTimeout(() => { id = setInterval(() => { k++; setN(Math.round(v * k / steps)); if (k >= steps && id) { clearInterval(id); id = null; } }, 30); }, d);
    return () => { clearTimeout(t0); if (id) clearInterval(id); };
  }, []);
  const a = useAnimatedStyle(() => ({ opacity: sc.value, transform: [{ scale: .5 + sc.value * .5 }] }));
  return (
    <Animated.View style={[{ flex: 1, padding: 4 }, a]}>
      <Panel style={{ alignItems: 'center', paddingVertical: 10 }} accent={c}>
        <Img src={img} style={{ width: 40, height: 40 }} />
        <T s={`${sign && n >= 0 ? '+' : n >= 0 ? '+' : ''}${n}${label ? ' ' + label : ''}`} style={{ fontFamily: F.title, fontSize: 15, color: c, marginTop: 2 }} />
      </Panel>
    </Animated.View>
  );
}

const s = StyleSheet.create({
  say: { flex: 1, marginRight: 8, marginBottom: 24, padding: 10, borderRadius: 16, borderBottomRightRadius: 4, backgroundColor: 'rgba(14,30,80,.9)', borderWidth: 1, borderColor: 'rgba(92,225,255,.4)' },
});
