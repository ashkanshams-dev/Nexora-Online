// Prominent "آنلاین" entry card (Home + Play): 3D tilt on press, shine sweep, quick links.
import React, { memo, useEffect } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { UI, UI2 } from '../game/assets';
import { Img, Press, T } from '../ui/kit';
import { C, F, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import type { OnlineEntry } from '../nav';

function OnlineCard({ onOnline }: { onOnline: (e?: OnlineEntry) => void }) {
  const { profile } = useAuth();
  const rx = useSharedValue(0), ry = useSharedValue(0), sh = useSharedValue(0);
  useEffect(() => { sh.value = withRepeat(withSequence(withDelay(1800, withTiming(1, { duration: 1300, easing: Easing.inOut(Easing.quad) })), withTiming(0, { duration: 0 })), -1, false); }, []);
  const tilt = useAnimatedStyle(() => ({ transform: [{ perspective: 700 }, { rotateX: `${rx.value}deg` }, { rotateY: `${ry.value}deg` }, { scale: 1 - Math.abs(rx.value) * .004 }] }));
  const shine = useAnimatedStyle(() => ({ transform: [{ translateX: -120 + sh.value * 620 }, { rotate: '20deg' }], opacity: sh.value > 0 && sh.value < 1 ? 1 : 0 }));
  const links: [OnlineEntry, string, any][] = [['arena', 'آرنا', UI2.x_crown], ['tours', 'تورنمنت', UI2.x_trophy], ['leagues', 'لیگ', UI2.x_medal], ['challenges', 'چالش', UI2.c_calendar]];
  return (
    <View>
      <Pressable
        onPressIn={e => { const { locationX: x, locationY: y } = e.nativeEvent; ry.value = withSpring((x / 340 - .5) * -10, { damping: 14 }); rx.value = withSpring((y / 120 - .5) * 10, { damping: 14 }); }}
        onPressOut={() => { rx.value = withSpring(0, { damping: 10 }); ry.value = withSpring(0, { damping: 10 }); }}
        onPress={() => { sfx('ui'); buzz('medium'); onOnline('hub'); }}>
        <Animated.View style={[st.card, tilt]}>
          <LinearGradient colors={['#3a1d8a', '#1b2f8f', '#0a5a8a']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
          <LinearGradient colors={['rgba(255,255,255,.3)', 'rgba(255,255,255,0)']} style={[StyleSheet.absoluteFill, { height: '50%' }]} />
          <Animated.View style={[st.shine, shine]} />
          <Img src={UI.portal_globe} style={{ width: 84, height: 84 }} />
          <View style={{ flex: 1, alignItems: 'flex-end', marginRight: 8 }}>
            <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
              <T s="آنلاین" style={{ fontFamily: F.title, fontSize: 24, color: '#fff', textShadowColor: C.cyan, textShadowRadius: 12 }} />
              <View style={st.live}><View style={st.dot} /><T s="LIVE" style={{ fontFamily: F.head, fontSize: 9, color: '#fff', letterSpacing: 1 }} /></View>
            </View>
            <T s="مسابقه با بازیکن‌های واقعی · ۱ به ۱، ۲ به ۲، ۳ به ۳" n={2} style={{ fontSize: 12, color: '#d6e6ff', marginTop: 2, textAlign: 'right' }} />
            {profile ? <T s={`امتیاز ${fa(profile.rating)} · 💎 ${fa(profile.gems)}`} style={{ fontFamily: F.bold, fontSize: 11, color: C.gold, marginTop: 4 }} /> : null}
          </View>
        </Animated.View>
      </Pressable>
      <View style={{ flexDirection: 'row-reverse', marginTop: 8 }}>
        {links.map(([k, l, img], i) => (
          <Press key={k} onPress={() => onOnline(k)} style={[st.link, { marginLeft: i < links.length - 1 ? 8 : 0 }]}>
            <Img src={img} style={{ width: 26, height: 26 }} />
            <T s={l} n={1} style={{ fontFamily: F.bold, fontSize: 11, marginRight: 4 }} />
          </Press>
        ))}
      </View>
    </View>
  );
}
export default memo(OnlineCard);

const st = StyleSheet.create({
  card: { height: 112, borderRadius: 24, overflow: 'hidden', flexDirection: 'row-reverse', alignItems: 'center', paddingHorizontal: 14, borderWidth: 1.5, borderColor: 'rgba(160,220,255,.55)', shadowColor: C.violet, shadowOpacity: .7, shadowRadius: 18, shadowOffset: { width: 0, height: 0 }, elevation: 12 },
  shine: { position: 'absolute', top: -40, left: 0, width: 50, height: 200, backgroundColor: 'rgba(255,255,255,.22)' },
  live: { flexDirection: 'row', alignItems: 'center', height: 18, paddingHorizontal: 6, borderRadius: 9, backgroundColor: C.red, marginRight: 8 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#fff', marginRight: 4 },
  link: { flex: 1, height: 44, borderRadius: 14, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(10,16,44,.85)', borderWidth: 1, borderColor: C.line },
});
