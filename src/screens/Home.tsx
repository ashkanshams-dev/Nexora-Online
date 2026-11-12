// Home: hero (selected disc on a floating hologram pedestal + Play), max 4 quick actions,
// daily reward + daily challenges. Everything else lives in Play / Profile / Settings.
import React, { memo, useEffect } from 'react';
import { ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, interpolate, useAnimatedScrollHandler, useAnimatedStyle, useSharedValue, withRepeat, withSequence, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { TEAM_IMG } from '../game/assets';
import { teamById, teamKey } from '../game/util';
import { useStore } from '../store';
import { Enter, Img, Panel, Press, Pulse, Section, T } from '../ui/kit';
import { C, F, G, IC, SP, TY, fa, glow } from '../ui/theme';
import { MENU } from '../ui/menuAssets';
import { MODES, Mode } from './Setup';
import type { OnlineEntry } from '../nav';
import { HomeChallenges } from '../online/Challenges';
import { useNav } from '../nav';

type Props = { top: number; bottom: number; onOnline: (e?: OnlineEntry) => void; onMode: (m: Mode) => void; onTab: (t: 'team' | 'shop' | 'play' | 'profile' | 'social') => void; onDaily: () => void; onSettings: () => void; onChest: () => void; dailyReady: boolean; chestReady: boolean };

function Home({ top, bottom, onOnline, onMode, onTab, onDaily, onChest, dailyReady, chestReady }: Props) {
  const { width: W } = useWindowDimensions();
  const { p } = useStore(); const me = teamById(p.team);
  const nav = useNav();
  const heroW = Math.min(W * .5, 240);
  const sy = useSharedValue(0);
  const onScroll = useAnimatedScrollHandler(e => { sy.value = e.contentOffset.y; });
  // parallax: the hero drifts slower than the content and tilts back slightly
  const par = useAnimatedStyle(() => ({ transform: [{ perspective: 800 }, { translateY: sy.value * .35 }, { rotateX: `${interpolate(sy.value, [0, 240], [0, 18], 'clamp')}deg` }], opacity: interpolate(sy.value, [0, 260], [1, .35], 'clamp') }));
  const quick: { img: any; label: string; on: () => void; dot?: boolean }[] = [
    { img: MENU.ic_friends, label: 'آنلاین', on: () => onOnline('hub') },
    { img: MENU.ic_trophy, label: 'جام نکسورا', on: () => onMode(MODES[1]) },
    { img: MENU.shield_star, label: 'تیم من', on: () => onTab('team') },
    { img: MENU.ic_gift, label: 'صندوقچه', on: onChest, dot: chestReady },
  ];
  return (
    <Animated.ScrollView onScroll={onScroll} scrollEventThrottle={16} contentContainerStyle={{ paddingTop: top, paddingBottom: bottom + SP.l }} showsVerticalScrollIndicator={false}>
      {/* hero */}
      <Animated.View style={[{ alignItems: 'center', height: heroW + 120, justifyContent: 'flex-end' }, par]}>
        <Img src={MENU.logo} style={{ position: 'absolute', top: 0, width: Math.min(W * .62, 300), height: Math.min(W * .62, 300) * .48 }} />
        <Pulse size={heroW * .9} color="rgba(79,140,255,.28)" style={{ bottom: 40 }} />
        <Img src={MENU.pedestal} style={{ position: 'absolute', bottom: 0, width: heroW * 1.5, height: heroW * 1.5 * .42 }} />
        <Hover>
          <View style={[s.disc, { width: heroW * .78, height: heroW * .78, borderRadius: heroW }, glow(C.cyan, 22, .75)]}>
            <Img src={TEAM_IMG[teamKey(me)]} style={{ width: heroW * .74, height: heroW * .74, borderRadius: heroW }} />
          </View>
        </Hover>
      </Animated.View>
      <Press onPress={() => onTab('team')} style={{ alignSelf: 'center', minHeight: 44, justifyContent: 'center', paddingHorizontal: SP.l }}>
        <T s={`${me.name}  ·  تغییر تیم ›`} n={1} style={{ fontFamily: F.bold, fontSize: TY.small, color: C.dim }} />
      </Press>

      <Enter i={0} style={{ paddingHorizontal: SP.l, marginTop: SP.s }}>
        <PlayButton onPress={() => onMode(MODES[0])} />
      </Enter>

      {/* quick actions (max 4) */}
      <Enter i={1} style={{ flexDirection: 'row-reverse', paddingHorizontal: SP.m, marginTop: SP.l }}>
        {quick.map(q => (
          <Press key={q.label} onPress={q.on} style={{ flex: 1, marginHorizontal: SP.xs }} scaleTo={.94}>
            <View style={s.quick}>
              <Img src={q.img} style={{ width: 40, height: 40 }} />
              <T s={q.label} n={1} style={{ fontFamily: F.bold, fontSize: TY.cap, marginTop: SP.xs }} />
              {q.dot ? <View style={s.dot} /> : null}
            </View>
          </Press>
        ))}
      </Enter>

      {/* daily reward */}
      <Section title="جایزه‌ی روزانه">
        <Enter i={2} style={{ paddingHorizontal: SP.l }}>
          <Press onPress={onDaily} scaleTo={.98}>
            <Panel style={{ flexDirection: 'row-reverse', alignItems: 'center', padding: SP.m }} accent={dailyReady ? C.gold : 'transparent'} glow={dailyReady}>
              <Img src={MENU.ic_gift} style={{ width: 40, height: 40 }} />
              <View style={{ flex: 1, marginHorizontal: SP.m, alignItems: 'flex-end' }}>
                <T s={dailyReady ? 'جایزه‌ی امروز آماده‌ست!' : `روز ${fa(p.streak || 0)} از ۷`} style={{ fontFamily: F.bold, fontSize: TY.body }} />
                <T s={dailyReady ? 'سکه و الماس رایگان؛ هر روز بزرگ‌تر' : 'فردا دوباره سر بزن'} style={{ fontSize: TY.cap, color: C.dim }} />
              </View>
              <View style={[s.cta, { borderColor: dailyReady ? C.gold : C.line }]}>
                <T s={dailyReady ? 'دریافت' : 'جزئیات'} style={{ fontFamily: F.bold, fontSize: TY.small, color: dailyReady ? C.gold : C.dim }} />
              </View>
            </Panel>
          </Press>
        </Enter>
      </Section>

      {/* daily challenges */}
      <Section title="چالش‌های امروز" action="همه ›" onAction={() => onOnline('challenges')}>
        <Enter i={3} style={{ paddingHorizontal: SP.l }}>
          <HomeChallenges toast={nav.toast} onAll={() => onOnline('challenges')} />
        </Enter>
      </Section>
    </Animated.ScrollView>
  );
}
export default memo(Home);
void ScrollView; void IC;

function Hover({ children }: { children: React.ReactNode }) {
  const t = useSharedValue(0);
  useEffect(() => { t.value = withRepeat(withTiming(1, { duration: 2800, easing: Easing.inOut(Easing.sin) }), -1, true); }, []);
  const a = useAnimatedStyle(() => ({ transform: [{ translateY: -heroLift(t.value) }, { perspective: 600 }, { rotateY: `${(t.value - .5) * 14}deg` }] }));
  return <Animated.View style={[{ marginBottom: 46 }, a]}>{children}</Animated.View>;
}
const heroLift = (v: number) => { 'worklet'; return 6 + v * 10; };

function PlayButton({ onPress }: { onPress: () => void }) {
  const sh = useSharedValue(0);
  useEffect(() => { sh.value = withRepeat(withSequence(withTiming(1, { duration: 1600, easing: Easing.inOut(Easing.quad) }), withTiming(1, { duration: 900 })), -1, false); }, []);
  const shine = useAnimatedStyle(() => ({ transform: [{ translateX: -160 + sh.value * 560 }, { rotate: '20deg' }] }));
  return (
    <Press onPress={onPress} scaleTo={.96}>
      <View style={s.play}>
        <LinearGradient colors={G.primary as any} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
        <LinearGradient colors={['rgba(255,255,255,.4)', 'rgba(255,255,255,.05)', 'rgba(255,255,255,0)']} style={[StyleSheet.absoluteFill, { height: '55%' }]} />
        <Animated.View style={[s.shine, shine]} />
        <Img src={MENU.ic_play} style={{ width: 40, height: 40, marginRight: SP.s }} />
        <View style={{ alignItems: 'center' }}>
          <T s="شروع بازی" style={{ fontFamily: F.title, fontSize: 22, color: '#fff', textShadowColor: 'rgba(0,0,40,.5)', textShadowRadius: 8 }} />
          <T s="QUICK MATCH" style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: 'rgba(255,255,255,.85)' }} />
        </View>
      </View>
    </Press>
  );
}

const s = StyleSheet.create({
  disc: { alignItems: 'center', justifyContent: 'center', backgroundColor: '#05040E', borderWidth: 3, borderColor: 'rgba(120,220,255,.85)' },
  play: { height: 68, borderRadius: 22, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: 'rgba(255,255,255,.5)', shadowColor: C.cyan, shadowOpacity: .7, shadowRadius: 20, shadowOffset: { width: 0, height: 0 }, elevation: 14 },
  shine: { position: 'absolute', top: -40, width: 60, height: 160, backgroundColor: 'rgba(255,255,255,.28)' },
  quick: { height: 84, borderRadius: 18, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(10,14,40,.82)', borderWidth: 1, borderColor: C.line },
  dot: { position: 'absolute', top: 6, right: 10, width: 10, height: 10, borderRadius: 5, backgroundColor: C.red, borderWidth: 2, borderColor: '#0b1236' },
  cta: { height: 36, minWidth: 64, paddingHorizontal: SP.m, borderRadius: 18, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
});
