import React, { memo, useEffect } from 'react';
import { Image, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, FadeIn, useAnimatedStyle, useSharedValue, withRepeat, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { UI, UI2 } from '../game/assets';
import { MENU } from './menuAssets';

// Deep-space backdrop. Everything animates on the UI thread (Reanimated transforms on
// pre-baked images): no full-screen shader, no per-frame JS.
export type SpaceTheme = 'base' | 'win' | 'lose' | 'system' | 'hub' | 'stadium' | 'holo';
const NEB: Record<SpaceTheme, any> = { base: UI.neb_base, win: UI.neb_win, lose: UI.neb_lose, system: UI.neb_system, hub: UI2.home_bg, stadium: MENU.bg_stadium, holo: MENU.bg_holo };
void UI2;
const TILE = 1024;

const StarLayer = memo(function StarLayer({ src, period, opacity }: { src: any; period: number; opacity: number }) {
  const { width: W, height: H } = useWindowDimensions();
  const t = useSharedValue(0);
  useEffect(() => { t.value = withRepeat(withTiming(1, { duration: period, easing: Easing.linear }), -1, false); }, []);
  const st = useAnimatedStyle(() => ({ transform: [{ translateY: -TILE + t.value * TILE }] }));
  const rows = Math.ceil(H / TILE) + 1, cols = Math.ceil(W / TILE);
  return (
    <Animated.View pointerEvents="none" style={[{ position: 'absolute', left: 0, top: 0, opacity }, st]}>
      {Array.from({ length: rows }).map((_, r) => (
        <View key={r} style={{ flexDirection: 'row' }}>
          {Array.from({ length: cols }).map((__, c) => <Image key={c} source={src} style={{ width: TILE, height: TILE }} />)}
        </View>
      ))}
    </Animated.View>
  );
});

function Space({ theme = 'base', dim = 0, stars = true }: { theme?: SpaceTheme; dim?: number; stars?: boolean }) {
  const { width: W, height: H } = useWindowDimensions();
  const b = useSharedValue(0);
  useEffect(() => { b.value = withRepeat(withTiming(1, { duration: 16000, easing: Easing.inOut(Easing.sin) }), -1, true); }, []);
  const neb = useAnimatedStyle(() => ({ transform: [{ scale: 1.05 + b.value * .05 }, { translateY: -6 + b.value * 12 }] }));
  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: '#02030b', overflow: 'hidden' }]}>
      <Animated.View key={theme} entering={FadeIn.duration(600)} style={[StyleSheet.absoluteFill, neb]}>
        <Image source={NEB[theme]} style={{ width: W, height: H }} resizeMode="cover" />
      </Animated.View>
      {stars ? <StarLayer src={UI.stars1} period={110000} opacity={.7} /> : null}
      {stars ? <StarLayer src={UI.stars2} period={60000} opacity={.75} /> : null}
      <LinearGradient colors={theme === 'stadium' || theme === 'holo' ? [`rgba(5,4,14,${.55 + dim})`, `rgba(5,4,14,${.45 + dim})`, `rgba(5,4,14,${.82 + dim})`] : [`rgba(2,4,14,${.35 + dim})`, `rgba(2,4,14,${dim})`, `rgba(2,4,14,${.55 + dim})`]} locations={[0, .45, 1]} style={StyleSheet.absoluteFill} />
    </View>
  );
}
export default memo(Space);
