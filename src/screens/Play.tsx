import React, { memo, useState } from 'react';
import { ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Extrapolation, interpolate, useAnimatedScrollHandler, useAnimatedStyle, useSharedValue, SharedValue } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { UI, UI2 } from '../game/assets';
import { LEAGUES, LEAGUE_FA, league, useStore } from '../store';
import { Btn, Enter, Float, Img, Panel, Press, Pulse, T, Title } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { MODES, Mode } from './Setup';
import type { OnlineEntry } from '../nav';
import OnlineCard from './OnlineCard';

const MEDAL = ['medal_bronze', 'medal_silver', 'medal_gold', 'medal_epic', 'shield_epic', 'shield_crown'];

function Play({ top, bottom, onMode, onOnline }: { top: number; bottom: number; onMode: (m: Mode) => void; onOnline: (e?: OnlineEntry) => void }) {
  const { width: W } = useWindowDimensions();
  const { p } = useStore(); const lg = league(p.trophies);
  const cw = Math.min(W * .72, 330), gap = 14, side = (W - cw) / 2, snap = cw + gap;
  const x = useSharedValue(0);
  const [idx, setIdx] = useState(0);
  const onScroll = useAnimatedScrollHandler(e => { x.value = e.contentOffset.x; });
  const m = MODES[idx];
  return (
    <ScrollView contentContainerStyle={{ paddingTop: top, paddingBottom: bottom + 10 }} showsVerticalScrollIndicator={false}>
      <Enter i={0} style={{ alignItems: 'center', marginTop: 4 }}>
        <T s="PORTAL · SELECT" style={{ fontFamily: F.head, fontSize: 10, letterSpacing: 5, color: C.cyan }} />
        <T s="انتخاب حالت بازی" style={{ fontFamily: F.title, fontSize: 22, marginTop: 2 }} />
      </Enter>

      <View style={{ paddingHorizontal: 16, marginTop: 12 }}><OnlineCard onOnline={onOnline} /></View>
      <Title s="آفلاین" en="OFFLINE · BOT & LOCAL" />
      <Animated.ScrollView horizontal showsHorizontalScrollIndicator={false} snapToInterval={snap} decelerationRate="fast"
        contentContainerStyle={{ paddingHorizontal: side - gap / 2, paddingVertical: 16 }} onScroll={onScroll} scrollEventThrottle={16}
        onMomentumScrollEnd={e => setIdx(Math.max(0, Math.min(MODES.length - 1, Math.round(e.nativeEvent.contentOffset.x / snap))))}>
        {MODES.map((mm, i) => <Card key={mm.k} m={mm} i={i} x={x} w={cw} gap={gap} snap={snap} onPress={() => onMode(mm)} />)}
      </Animated.ScrollView>

      <View style={{ flexDirection: 'row', justifyContent: 'center', marginTop: 2 }}>
        {MODES.map((mm, i) => <Dot key={mm.k} i={i} x={x} snap={snap} color={mm.color} />)}
      </View>

      <View style={{ paddingHorizontal: 24, marginTop: 14 }}>
        <Btn label={`ورود به ${m.name}`} onPress={() => onMode(m)} colors={m.k === 'cup' ? G.gold : m.k === 'galaxy' ? G.violet : m.k === 'local' ? G.green : G.primary} />
      </View>

      {/* league road */}
      <Title s="جاده‌ی لیگ" en="LEAGUE ROAD" accent={C.gold} />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12, alignItems: 'center' }}>
        {LEAGUES.map(([n, t], i) => {
          const reached = p.trophies >= t, cur = i === lg.idx;
          return (
            <View key={n} style={{ flexDirection: 'row', alignItems: 'center' }}>
              {i ? <View style={[s.road, reached && { backgroundColor: C.gold }]} /> : null}
              <View style={[s.medal, cur && { borderColor: C.gold, backgroundColor: 'rgba(255,210,87,.12)', shadowColor: C.gold, shadowOpacity: .8, shadowRadius: 12 }]}>
                <Img src={(UI as any)[MEDAL[i]]} style={{ width: 54, height: 54, opacity: reached ? 1 : .35 }} />
                <T s={LEAGUE_FA[n]} style={{ fontSize: 11, color: reached ? '#fff' : C.dim2 }} />
                <T s={fa(t)} style={{ fontFamily: F.head, fontSize: 9, color: reached ? C.gold : C.dim2 }} />
              </View>
            </View>
          );
        })}
      </ScrollView>

    </ScrollView>
  );
}
export default memo(Play);

function Card({ m, i, x, w, gap, snap, onPress }: { m: Mode; i: number; x: SharedValue<number>; w: number; gap: number; snap: number; onPress: () => void }) {
  const a = useAnimatedStyle(() => {
    const d = (x.value - i * snap) / snap;
    return {
      opacity: interpolate(Math.abs(d), [0, 1, 2], [1, .55, .25], Extrapolation.CLAMP),
      transform: [{ perspective: 900 }, { rotateY: `${interpolate(d, [-1, 0, 1], [28, 0, -28], Extrapolation.CLAMP)}deg` }, { scale: interpolate(Math.abs(d), [0, 1], [1, .84], Extrapolation.CLAMP) }],
    };
  });
  const art = useAnimatedStyle(() => { const d = (x.value - i * snap) / snap; return { transform: [{ translateX: d * 40 }] }; });
  return (
    <Animated.View style={[{ width: w, marginHorizontal: gap / 2 }, a]}>
      <Press onPress={onPress} scaleTo={.97}>
        <View style={[s.card, { height: w * 1.32, borderColor: m.color + '88', shadowColor: m.color }]}>
          <LinearGradient colors={[m.color + '55', 'rgba(14,22,64,.85)', 'rgba(5,8,24,.98)']} style={StyleSheet.absoluteFill} />
          <Img src={UI2.portal} style={{ position: 'absolute', top: 10, width: w * 1.05, height: w * .7, opacity: .42 }} />
          <Animated.View style={[{ alignItems: 'center', marginTop: w * .1 }, art]}>
            <Pulse size={w * .45} color={m.color + '55'} style={{ top: w * .08 }} />
            <Float amp={6} dur={2600}><Img src={m.img} style={{ width: w * .58, height: w * .62 }} /></Float>
          </Animated.View>
          <View style={{ position: 'absolute', bottom: 18, left: 16, right: 16, alignItems: 'center' }}>
            <T s={m.en} style={{ fontFamily: F.head, fontSize: 10, letterSpacing: 3, color: m.color }} />
            <T s={m.name} style={{ fontFamily: F.title, fontSize: 24, marginTop: 2, textShadowColor: m.color, textShadowRadius: 14 }} />
            <T s={m.desc} style={{ fontSize: 12, color: '#c6dbff', textAlign: 'center', marginTop: 4 }} n={2} />
            <View style={[s.rw, { borderColor: m.color + '66' }]}><Img src={UI2.c_coin} style={{ width: 20, height: 20, marginLeft: 4 }} /><T s={m.reward} n={1} style={{ fontSize: 11, color: '#ffe9a8' }} /></View>
          </View>
        </View>
      </Press>
    </Animated.View>
  );
}

function Dot({ i, x, snap, color }: { i: number; x: SharedValue<number>; snap: number; color: string }) {
  const a = useAnimatedStyle(() => { const d = Math.abs(x.value / snap - i); const k = Math.max(0, 1 - d); return { width: 8 + k * 18, opacity: .35 + k * .65 }; });
  return <Animated.View style={[{ height: 8, borderRadius: 4, marginHorizontal: 3, backgroundColor: color }, a]} />;
}

const s = StyleSheet.create({
  card: { borderRadius: 28, borderWidth: 1.5, overflow: 'hidden', alignItems: 'center', backgroundColor: '#0a1030', shadowOpacity: .6, shadowRadius: 18, shadowOffset: { width: 0, height: 0 }, elevation: 12 },
  rw: { flexDirection: 'row-reverse', alignItems: 'center', marginTop: 8, paddingHorizontal: 10, height: 28, borderRadius: 14, borderWidth: 1, backgroundColor: 'rgba(0,0,0,.25)' },
  road: { width: 26, height: 4, borderRadius: 2, backgroundColor: 'rgba(255,255,255,.12)' },
  medal: { width: 86, alignItems: 'center', paddingVertical: 8, borderRadius: 18, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(8,12,34,.8)' },
});
