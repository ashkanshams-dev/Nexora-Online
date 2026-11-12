// App chrome: bottom tab bar, top HUD and bottom sheet.
import React, { forwardRef, memo, useEffect, useImperativeHandle, useRef } from 'react';
import { BackHandler, PanResponder, Pressable, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, runOnJS, useAnimatedStyle, useSharedValue, withRepeat, withSpring, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TEAM_IMG, UI, UI2 } from '../game/assets';
import { teamById, teamKey } from '../game/util';
import { level, useStore } from '../store';
import { IconButton, Img, Pill, Press, T } from './kit';
import { MENU } from './menuAssets';
import { C, F, fa } from './theme';
import { buzz, sfx } from '../sound';
import { useAuth } from '../net/auth';
import { levelProgress } from '../net/supabase';
import { discImg } from '../online/ui';

export type Tab = 'home' | 'social' | 'play' | 'shop' | 'profile';
const TABS: { k: Tab; label: string; icon: any }[] = [
  { k: 'home', label: 'خانه', icon: MENU.ic_home },
  { k: 'play', label: 'بازی', icon: MENU.ic_play },
  { k: 'social', label: 'اجتماعی', icon: MENU.ic_friends },
  { k: 'shop', label: 'فروشگاه', icon: MENU.ic_shop },
  { k: 'profile', label: 'پروفایل', icon: MENU.ic_trophy },
];

export const TAB_H = 74;

export const TabBar = memo(function TabBar({ tab, onTab, badge }: { tab: Tab; onTab: (t: Tab) => void; badge?: Partial<Record<Tab, boolean>> }) {
  const ins = useSafeAreaInsets(); const { width: W } = useWindowDimensions();
  const barW = Math.min(W - 20, 520), cw = barW / TABS.length;
  const idx = TABS.findIndex(t => t.k === tab);
  const x = useSharedValue(idx);
  useEffect(() => { x.value = withSpring(idx, { damping: 17, stiffness: 210, mass: .8 }); }, [idx]);
  const hl = useAnimatedStyle(() => ({ transform: [{ translateX: -x.value * cw }] }));
  return (
    <View pointerEvents="box-none" style={[s.tabWrap, { paddingBottom: Math.max(10, ins.bottom) }]}>
      <View style={[s.tabBar, { width: barW }]}>
        <LinearGradient colors={['rgba(22,34,86,.96)', 'rgba(8,12,36,.98)']} style={[StyleSheet.absoluteFill, { borderRadius: 26 }]} />
        <View style={s.tabLine} />
        <Animated.View style={[s.tabHl, { width: cw - 12, right: 6 }, hl]}>
          <LinearGradient colors={['rgba(79,227,255,.28)', 'rgba(109,91,255,.10)']} style={[StyleSheet.absoluteFill, { borderRadius: 20 }]} />
          <View style={s.tabDot} />
        </Animated.View>
        {TABS.map((t, i) => <TabBtn key={t.k} t={t} on={i === idx} onPress={() => onTab(t.k)} badge={!!badge?.[t.k]} />)}
      </View>
    </View>
  );
});

function TabBtn({ t, on, onPress, badge }: { t: typeof TABS[0]; on: boolean; onPress: () => void; badge: boolean }) {
  const sc = useSharedValue(on ? 1 : 0);
  useEffect(() => { sc.value = withSpring(on ? 1 : 0, { damping: 12, stiffness: 240 }); }, [on]);
  const a = useAnimatedStyle(() => ({ opacity: .62 + sc.value * .38, transform: [{ translateY: -sc.value * 2 }] }));
  const lb = useAnimatedStyle(() => ({ opacity: .55 + sc.value * .45 }));
  return (
    <Pressable style={s.tabBtn} onPress={() => { if (!on) { sfx('ui'); buzz('light'); } onPress(); }}>
      <Animated.View style={a}><Img src={t.icon} style={{ width: 30, height: 30 }} /></Animated.View>
      <Animated.View style={lb}><T s={t.label} style={{ fontFamily: F.bold, fontSize: 10, color: on ? C.cyan : C.dim, marginTop: 2 }} /></Animated.View>
      {badge ? <View style={s.badge} /> : null}
    </Pressable>
  );
}

// ---------- top HUD ----------
export const Hud = memo(function Hud({ onProfile, onSettings, onDaily, dailyReady, onShop }: { onProfile: () => void; onSettings: () => void; onDaily: () => void; dailyReady: boolean; onShop: () => void }) {
  const ins = useSafeAreaInsets();
  const { p } = useStore(); const { profile } = useAuth();
  // signed in → show the online identity (level / XP / gems from the server); otherwise the local profile
  const lp = profile ? levelProgress(profile.xp) : null;
  const local = level(p.xp), me = teamById(p.team);
  const lv = lp ? { level: lp.level, cur: lp.cur, need: lp.need } : local;
  const name = profile?.username || p.name;
  const avatar = profile ? (profile.avatar_url ? { uri: profile.avatar_url } : discImg(profile.equipped_disc)) : TEAM_IMG[teamKey(me)];
  return (
    <View style={[s.hud, { paddingTop: ins.top + 6 }]}>
      <LinearGradient pointerEvents="none" colors={['rgba(2,4,14,.92)', 'rgba(2,4,14,.55)', 'transparent']} style={StyleSheet.absoluteFill} />
      <Press onPress={onProfile} style={s.me}>
        <View style={{ alignItems: 'flex-end', marginRight: 8, maxWidth: 110 }}>
          <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: 13 }} />
          <View style={s.xpTrack}><View style={[s.xpFill, { width: `${Math.max(4, lv.cur / lv.need * 100)}%` }]} /></View>
        </View>
        <View>
          <View style={s.av}><Img src={avatar} fit={profile?.avatar_url ? 'cover' : 'contain'} style={{ width: 36, height: 36, borderRadius: 18 }} /></View>
          <View style={s.lvl}><T s={String(lv.level)} style={{ fontFamily: F.title, fontSize: 9, color: '#04122a' }} /></View>
        </View>
      </Press>
      <View style={{ flex: 1 }} />
      <Pill icon={MENU.g_gem} v={profile ? profile.gems : p.gems} onPress={onShop} />
      <Pill icon={MENU.g_coin} v={p.coins} tint={C.gold} onPress={onShop} plus />
      <GiftBtn ready={dailyReady} onPress={onDaily} />
      <IconButton src={MENU.ic_settings} onPress={onSettings} />
    </View>
  );
});

function GiftBtn({ ready, onPress }: { ready: boolean; onPress: () => void }) {
  const w = useSharedValue(0);
  useEffect(() => { if (ready) w.value = withRepeat(withTiming(1, { duration: 900, easing: Easing.inOut(Easing.sin) }), -1, true); else w.value = withTiming(0); }, [ready]);
  const a = useAnimatedStyle(() => ({ transform: [{ rotate: `${(w.value - .5) * 16}deg` }, { scale: 1 + w.value * .08 }] }));
  return (
    <Press onPress={onPress} scaleTo={.88} style={s.iconBtn}>
      <Animated.View style={a}><Img src={MENU.ic_gift} style={{ width: 40, height: 40 }} /></Animated.View>
      {ready ? <View style={s.badge2} /> : null}
    </Press>
  );
}

// ---------- bottom sheet (spring in, drag the handle down to dismiss, Android back closes) ----------
export type SheetHandle = { close: () => void };
export const Sheet = forwardRef<SheetHandle, { onClosed: () => void; children: React.ReactNode; title?: string; en?: string; height?: number; accent?: string }>(function Sheet({ onClosed, children, title, en, height = .84, accent = C.cyan }, ref) {
  const { height: H } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const h = Math.min(H * height, H - ins.top - 20);
  const y = useSharedValue(h), bd = useSharedValue(0);
  const closing = useRef(false);
  useEffect(() => { y.value = withSpring(0, { damping: 20, stiffness: 190, mass: .9 }); bd.value = withTiming(1, { duration: 250 }); }, []);
  const close = () => {
    if (closing.current) return; closing.current = true; buzz('light');
    bd.value = withTiming(0, { duration: 220 });
    y.value = withTiming(h, { duration: 240, easing: Easing.in(Easing.cubic) }, f => { if (f) runOnJS(onClosed)(); });
  };
  useImperativeHandle(ref, () => ({ close }));
  useEffect(() => { const sub = BackHandler.addEventListener('hardwareBackPress', () => { close(); return true; }); return () => sub.remove(); }, []);
  const pan = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true, onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dy) > 4,
    onPanResponderMove: (_, g) => { y.value = Math.max(0, g.dy); },
    onPanResponderRelease: (_, g) => { if (g.dy > h * .22 || g.vy > 1) close(); else y.value = withSpring(0, { damping: 18, stiffness: 220 }); },
    onPanResponderTerminate: () => { y.value = withSpring(0); },
  })).current;
  const sa = useAnimatedStyle(() => ({ transform: [{ translateY: y.value }] }));
  const ba = useAnimatedStyle(() => ({ opacity: bd.value }));
  return (
    <View style={[StyleSheet.absoluteFill, { zIndex: 60 }]}>
      <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(1,3,12,.72)' }, ba]}><Pressable style={StyleSheet.absoluteFill} onPress={close} /></Animated.View>
      <Animated.View style={[s.sheet, { height: h + 40, paddingBottom: 40, borderColor: accent + '55', shadowColor: accent }, sa]}>
        <LinearGradient colors={['#18245a', '#0b1236', '#060a22']} style={[StyleSheet.absoluteFill, { borderTopLeftRadius: 28, borderTopRightRadius: 28 }]} />
        <Img src={UI.scan} style={[StyleSheet.absoluteFill, { opacity: .5 }]} fit="cover" />
        <View {...pan.panHandlers} style={s.sheetHead}>
          <View style={[s.grip, { backgroundColor: accent }]} />
          {title ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', width: '100%', paddingHorizontal: 16, marginTop: 8 }}>
              <IconButton src={MENU.g_x} onPress={close} />
              <View style={{ flex: 1, alignItems: 'flex-end' }}>
                {en ? <T s={en} style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: accent }} /> : null}
                <T s={title} n={1} style={{ fontFamily: F.title, fontSize: 20, marginTop: 1 }} />
              </View>
            </View>
          ) : null}
        </View>
        <View style={{ flex: 1, paddingBottom: ins.bottom }}>{children}</View>
      </Animated.View>
    </View>
  );
});

// ---------- full-screen modal card (daily reward, chest, level up) ----------
export function Modal({ children, onClose, accent = C.gold }: { children: React.ReactNode; onClose: () => void; accent?: string }) {
  const sc = useSharedValue(.6), op = useSharedValue(0);
  useEffect(() => { sc.value = withSpring(1, { damping: 13, stiffness: 180 }); op.value = withTiming(1, { duration: 200 }); }, []);
  useEffect(() => { const sub = BackHandler.addEventListener('hardwareBackPress', () => { onClose(); return true; }); return () => sub.remove(); }, []);
  const a = useAnimatedStyle(() => ({ opacity: op.value, transform: [{ scale: sc.value }] }));
  const b = useAnimatedStyle(() => ({ opacity: op.value }));
  return (
    <View style={[StyleSheet.absoluteFill, { zIndex: 80, alignItems: 'center', justifyContent: 'center' }]}>
      <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(1,3,12,.8)' }, b]}><Pressable style={StyleSheet.absoluteFill} onPress={onClose} /></Animated.View>
      <Animated.View style={[{ width: '88%', maxWidth: 420, borderRadius: 26, borderWidth: 1, borderColor: accent + '88', overflow: 'hidden', shadowColor: accent, shadowOpacity: .6, shadowRadius: 30, shadowOffset: { width: 0, height: 0 }, elevation: 20 }, a]}>
        <LinearGradient colors={['#1d2a66', '#0c1238', '#070a22']} style={StyleSheet.absoluteFill} />
        {children}
      </Animated.View>
    </View>
  );
}

const s = StyleSheet.create({
  tabWrap: { position: 'absolute', left: 0, right: 0, bottom: 0, alignItems: 'center', zIndex: 40 },
  tabBar: { height: TAB_H - 8, borderRadius: 26, flexDirection: 'row-reverse', borderWidth: 1, borderColor: 'rgba(92,225,255,.28)', shadowColor: '#4c6bff', shadowOpacity: .5, shadowRadius: 20, shadowOffset: { width: 0, height: 4 }, elevation: 16 },
  tabLine: { position: 'absolute', top: 0, left: 40, right: 40, height: 1, backgroundColor: 'rgba(160,230,255,.45)' },
  tabHl: { position: 'absolute', top: 5, bottom: 5, borderRadius: 20, borderWidth: 1, borderColor: 'rgba(79,227,255,.45)' },
  tabDot: { position: 'absolute', bottom: 3, alignSelf: 'center', width: 18, height: 3, borderRadius: 2, backgroundColor: C.cyan, shadowColor: C.cyan, shadowOpacity: 1, shadowRadius: 6 },
  tabBtn: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  badge: { position: 'absolute', top: 8, right: '28%', width: 9, height: 9, borderRadius: 5, backgroundColor: C.red, borderWidth: 1.5, borderColor: '#0b1236' },
  badge2: { position: 'absolute', top: 3, right: 3, width: 9, height: 9, borderRadius: 5, backgroundColor: C.red, borderWidth: 1.5, borderColor: '#0b1236' },
  hud: { position: 'absolute', left: 0, right: 0, top: 0, zIndex: 30, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, paddingBottom: 14 },
  me: { flexDirection: 'row', alignItems: 'center', paddingVertical: 3, paddingLeft: 12, paddingRight: 3, borderRadius: 26, borderWidth: 1, borderColor: 'rgba(92,225,255,.35)', backgroundColor: 'rgba(8,14,40,.8)' },
  av: { width: 42, height: 42, borderRadius: 21, borderWidth: 2, borderColor: C.cyan, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' },
  lvl: { position: 'absolute', bottom: -4, alignSelf: 'center', minWidth: 20, height: 16, paddingHorizontal: 4, borderRadius: 8, backgroundColor: C.gold, alignItems: 'center', justifyContent: 'center' },
  xpTrack: { width: 70, height: 5, borderRadius: 3, backgroundColor: 'rgba(255,255,255,.12)', marginTop: 4, overflow: 'hidden' },
  xpFill: { height: '100%', borderRadius: 3, backgroundColor: C.cyan },
  iconBtn: { width: 44, height: 44, marginLeft: 2, alignItems: 'center', justifyContent: 'center' },
  sheet: { position: 'absolute', left: 0, right: 0, bottom: -40, borderTopLeftRadius: 28, borderTopRightRadius: 28, borderWidth: 1, overflow: 'hidden', shadowOpacity: .5, shadowRadius: 30, shadowOffset: { width: 0, height: -4 }, elevation: 24 },
  sheetHead: { alignItems: 'center', paddingTop: 8, paddingBottom: 6 },
  grip: { width: 46, height: 5, borderRadius: 3, opacity: .8 },
  x: { width: 40, height: 40, borderRadius: 20, borderWidth: 1, borderColor: 'rgba(255,255,255,.18)', backgroundColor: 'rgba(20,28,64,.9)', alignItems: 'center', justifyContent: 'center' },
});
void fa;
