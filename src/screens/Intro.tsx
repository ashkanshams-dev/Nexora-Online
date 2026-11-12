import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, runOnJS, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { Canvas, Fill, Group, Image as SkImg, Path, RadialGradient, Rect, useClock, useImage, usePathValue, vec } from '@shopify/react-native-skia';
import { useDerivedValue } from 'react-native-reanimated';
import { UI } from '../game/assets';
import { T } from '../ui/kit';
import { F } from '../ui/theme';
import { buzz, sfx } from '../sound';

// "Flight to Nexora": hyperspace warp drawn by Skia on the UI thread, a ringed planet growing
// out of the warp, then the NX logo slams in. Tap (or skip) to drop into the gate world.
const N = 240;

// distance travelled by the stars after t seconds (closed-form integral of the warp speed curve)
function travel(t: number) {
  'worklet';
  if (t < .5) return .12 * t + 2.38 * t * t * t / .75;
  const s05 = .12 * .5 + 2.38 * .125 / .75;
  if (t < 2.2) return s05 + 2.5 * (t - .5);
  const s22 = s05 + 2.5 * 1.7, u = Math.min(1, (t - 2.2) / 1.4);
  return s22 + .09 * (t - 2.2) + 2.41 * 1.4 * (1 - Math.pow(1 - u, 4)) / 4;
}
function speed(t: number) {
  'worklet';
  if (t < .5) return .12 + 2.38 * (t / .5) * (t / .5);
  if (t < 2.2) return 2.5;
  const u = Math.min(1, (t - 2.2) / 1.4); return .09 + 2.41 * Math.pow(1 - u, 3);
}

export default function Intro({ onDone }: { onDone: () => void }) {
  const { width: W, height: H } = useWindowDimensions();
  const clock = useClock();
  const stars = useMemo(() => {
    const a: number[] = [];
    for (let i = 0; i < N; i++) a.push((Math.random() - .5) * 2, (Math.random() - .5) * 2, Math.random());
    return a;
  }, []);
  const cx = W / 2, cy = H * .44, f = Math.max(W, H) * .3;

  const mk = (near: boolean) => usePathValue(b => {
    'worklet';
    const t = clock.value / 1000, S = travel(t), v = speed(t);
    for (let i = 0; i < N; i++) {
      let z = stars[i * 3 + 2] - S * .55; z = z - Math.floor(z); z = .02 + z * .98;
      if ((z < .45) !== near) continue;
      const pz = z + v * .07;
      const x1 = cx + stars[i * 3] / z * f, y1 = cy + stars[i * 3 + 1] / z * f;
      const x0 = cx + stars[i * 3] / pz * f, y0 = cy + stars[i * 3 + 1] / pz * f;
      b.moveTo(x0, y0); b.lineTo(x1 + .1, y1);
    }
  });
  const far = mk(false), near = mk(true);
  const planet = useImage(UI.planet);
  const pt = useDerivedValue(() => {
    const t = clock.value / 1000, p = Math.min(1, Math.max(0, (t - 1.8) / 2.4)), e = 1 - Math.pow(1 - p, 3);
    const sz = Math.min(W, H) * 1.1 * e;
    return [{ translateX: cx }, { translateY: cy }, { rotate: (t - 4) * .02 }, { translateX: -sz / 2 }, { translateY: -sz / 2 }, { scale: Math.max(.001, sz / 640) }];
  });
  const pop = useDerivedValue(() => Math.min(1, Math.max(0, ((clock.value / 1000) - 1.8) * .6)));
  const glow = useDerivedValue(() => .14 + Math.min(.3, speed(clock.value / 1000) * .1));

  const logo = useSharedValue(0), tag = useSharedValue(0), out = useSharedValue(0), pulse = useSharedValue(0);
  const [ready, setReady] = useState(false); const done = useRef(false);
  useEffect(() => {
    const a = setTimeout(() => { logo.value = withSpring(1, { damping: 9, stiffness: 120 }); tag.value = withDelay(500, withTiming(1, { duration: 800 })); sfx('whistle'); buzz('medium'); }, 3600);
    const b = setTimeout(() => { setReady(true); pulse.value = withRepeat(withTiming(1, { duration: 900 }), -1, true); }, 4600);
    return () => { clearTimeout(a); clearTimeout(b); };
  }, []);
  const enter = () => {
    if (done.current) return; done.current = true; buzz('medium');
    out.value = withTiming(1, { duration: 750, easing: Easing.out(Easing.cubic) }, fin => { if (fin) runOnJS(onDone)(); });
  };
  const lg = useAnimatedStyle(() => ({ opacity: Math.min(1, logo.value * 1.5), transform: [{ translateX: -Math.min(W * .7, 340) / 2 }, { translateY: -Math.min(W * .7, 340) / 2 }, { scale: .4 + .6 * logo.value }] }));
  const tg = useAnimatedStyle(() => ({ opacity: tag.value * .9 }));
  const tp = useAnimatedStyle(() => ({ opacity: .55 + pulse.value * .45, transform: [{ scale: 1 + pulse.value * .04 }] }));
  const wrap = useAnimatedStyle(() => ({ opacity: 1 - out.value, transform: [{ scale: 1 + out.value * .5 }] }));
  const flash = useAnimatedStyle(() => ({ opacity: logo.value > 0 && logo.value < .6 ? (.6 - logo.value) : 0 }));
  const LS = Math.min(W * .7, 340);

  return (
    <Animated.View style={[StyleSheet.absoluteFill, { zIndex: 100, backgroundColor: '#02030b' }, wrap]}>
      <Pressable style={StyleSheet.absoluteFill} onPress={() => { if (ready) enter(); }}>
        <Canvas style={StyleSheet.absoluteFill}>
          <Fill color="#02030b" />
          <Rect x={0} y={0} width={W} height={H} opacity={glow}>
            <RadialGradient c={vec(cx, cy)} r={Math.max(W, H) * .7} colors={['rgba(60,40,160,1)', 'rgba(0,0,0,0)']} />
          </Rect>
          <Path path={far} style="stroke" strokeWidth={1.1} strokeCap="round" color="rgba(150,200,255,0.55)" />
          <Path path={near} style="stroke" strokeWidth={2.4} strokeCap="round" color="rgba(200,180,255,0.95)" />
          {planet ? <Group transform={pt} opacity={pop}><SkImg image={planet} x={0} y={0} width={640} height={640} /></Group> : null}
        </Canvas>
        <Animated.Image source={UI.nx_logo} resizeMode="contain" style={[{ position: 'absolute', left: W / 2, top: cy, width: LS, height: LS }, lg]} />
        <Animated.View style={[{ position: 'absolute', left: 0, right: 0, top: cy + LS * .42, alignItems: 'center' }, tg]}>
          <T s="NEXORA · FINGER SOCCER" style={{ fontFamily: F.head, fontSize: 12, letterSpacing: 6, color: '#5ce1ff' }} />
        </Animated.View>
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: '#dff6ff' }, flash]} />
        {ready ? (
          <Animated.View style={[{ position: 'absolute', bottom: H * .13, alignSelf: 'center' }, tp]}>
            <Pressable onPress={enter} style={s.tap}><T s="برای ورود لمس کنید" style={{ fontFamily: F.bold, fontSize: 15 }} /></Pressable>
          </Animated.View>
        ) : null}
      </Pressable>
      <Pressable onPress={enter} style={s.skip}><T s="رد کردن ‹" style={{ fontSize: 13 }} /></Pressable>
    </Animated.View>
  );
}

const s = StyleSheet.create({
  tap: { paddingHorizontal: 26, paddingVertical: 12, borderRadius: 30, borderWidth: 1, borderColor: '#5ce1ff', backgroundColor: 'rgba(12,20,48,.8)', shadowColor: '#5ce1ff', shadowOpacity: .7, shadowRadius: 18 },
  skip: { position: 'absolute', top: 48, left: 16, paddingHorizontal: 16, height: 44, borderRadius: 22, justifyContent: 'center', backgroundColor: '#141a30', borderWidth: 1, borderColor: 'rgba(255,255,255,.2)' },
});
void View; void withSequence;
