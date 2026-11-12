import React, { memo, useCallback, useEffect, useMemo, useState } from 'react';
import { FlatList, ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withRepeat, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { BALL_IMG, FIELD_THUMB, TEAM_IMG, UI, UI2 } from '../game/assets';
import { BALL_NAMES, CATS, FIELDS, FORMS, TEAMS, TRAILS, Team as TeamT, ballPrice, fieldPrice, slots, teamPrice } from '../game/data';
import { RARITY, cardStats, rarity, teamById, teamKey } from '../game/util';
import { useStore } from '../store';
import { Bar, Btn, Chip, Img, Panel, Press, Pulse, Segment, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import { useDiscs, discStats, isFreeDisc } from '../net/discs';
import { useAuth } from '../net/auth';
import { StatBars } from '../online/ui';

type Toast = (m: string, k?: string) => void;
type Sub = 'disc' | 'ball' | 'field' | 'form';
const CAT_FA: Record<string, string> = { club: 'باشگاه', iran: 'لیگ ایران', nat: 'ملی', elite: 'الیت', emb: 'ملی ویژه', leg: 'افسانه NX', vip: 'ملی NX', car: 'خودرو', lux: 'لوکس', spt: 'ورزشی' };
const CAT_ORDER = ['club', 'iran', 'nat', 'elite', 'emb', 'leg', 'vip', 'car', 'lux', 'spt'];

function TeamScreen({ top, bottom, toast }: { top: number; bottom: number; toast: Toast }) {
  const [sub, setSub] = useState<Sub>('disc');
  return (
    <View style={{ flex: 1, paddingTop: top }}>
      <View style={{ paddingHorizontal: 16, marginBottom: 6 }}>
        <Segment value={sub} onChange={setSub} items={[['disc', 'دیسک'], ['ball', 'توپ'], ['field', 'زمین'], ['form', 'ترکیب']]} />
      </View>
      <View style={{ flex: 1 }}>
        {sub === 'disc' ? <Discs bottom={bottom} toast={toast} /> : sub === 'ball' ? <Balls bottom={bottom} toast={toast} /> : sub === 'field' ? <Fields bottom={bottom} toast={toast} /> : <Formation bottom={bottom} />}
      </View>
    </View>
  );
}
export default memo(TeamScreen);

// ---------- discs ----------
function Discs({ bottom, toast }: { bottom: number; toast: Toast }) {
  const { p, set } = useStore(); const { width: W } = useWindowDimensions();
  const [cat, setCat] = useState(teamById(p.team).cat);
  const [focus, setFocus] = useState(p.team);
  const list = useMemo(() => TEAMS.filter(t => t.cat === cat), [cat]);
  const cell = (W - 32 - 3 * 8) / 4;
  const dz = useDiscs(); const auth = useAuth();
  const [busy, setBusy] = useState(false);
  const ft = teamById(focus), owned = dz.has(ft.id), price = dz.catalog[ft.id]?.price_gems ?? (isFreeDisc(ft.id) ? 0 : teamPrice(ft)), ds = discStats(ft.id), rr = RARITY[rarity(ft)];
  const gems = auth.profile?.gems ?? 0;
  const act = async () => {
    if (busy) return;
    if (owned) {
      set({ team: ft.id }); buzz('success'); toast(`${ft.name} انتخاب شد`, 'ok');
      if (auth.uid) dz.equip(ft.id).then(r => { if (!r.ok) toast(r.error!, 'err'); });
      return;
    }
    setBusy(true);
    try {
      if (!auth.uid) { const id = await auth.ensure(); if (!id) { toast('برای خرید باید آنلاین باشی', 'err'); return; } }
      const g = auth.profile?.gems ?? 0;
      if (auth.profile && g < price) { toast(`${fa(price - g)} الماس دیگر لازم داری · چالش‌های روزانه و تورنمنت‌ها الماس می‌دهند`, 'err'); buzz('medium'); return; }
      const r = await dz.buy(ft.id);
      if (!r.ok) { toast(r.error!, 'err'); return; }
      await dz.equip(ft.id); set({ team: ft.id });
      sfx('win'); buzz('success'); toast(`${ft.name} باز شد! · 💎 ${fa(r.gems ?? 0)} باقی‌مانده`, 'ok');
    } finally { setBusy(false); }
  };
  const header = (
    <View>
      <DiscHero t={ft} color={rr.c} />
      <View style={{ alignItems: 'center' }}>
        <View style={[s.rar, { borderColor: rr.c + '88', backgroundColor: rr.c + '1c' }]}><T s={rr.n} style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: rr.c }} /></View>
        <T s={ft.name.toUpperCase()} n={1} style={{ fontFamily: F.title, fontSize: 20, letterSpacing: 1, marginTop: 4 }} />
      </View>
      <Panel style={{ marginHorizontal: 16, marginTop: 10, padding: 12 }} accent={rr.c}>
        <StatBars power={ds.power} accuracy={ds.accuracy} />
        <T s="قدرت = سرعت بیشینه‌ی ضربه · دقت = انحراف کمتر و پیش‌نمایش مسیر بلندتر" style={{ fontSize: 10, color: C.dim, marginTop: 6, textAlign: 'right' }} />
        <View style={{ marginTop: 10 }}>
          {p.team === ft.id ? <Btn label="انتخاب‌شده ✓" small colors={G.dark} disabled />
            : owned ? <Btn label="انتخاب این دیسک" small onPress={act} />
              : <Btn label={busy ? '…' : `خرید · 💎 ${fa(price)}`} sub={auth.profile ? `موجودی: ${fa(gems)} الماس` : undefined} small colors={G.violet} onPress={act} disabled={busy} />}
        </View>
      </Panel>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 14 }} contentContainerStyle={{ paddingHorizontal: 8 }}>
        {CAT_ORDER.filter(k => CATS.some(c => c[0] === k)).map(k => <Chip key={k} label={CAT_FA[k] || k} on={cat === k} onPress={() => setCat(k)} accent={k === 'leg' || k === 'vip' ? C.gold : k === 'emb' || k === 'chrome' ? C.violet : C.cyan} />)}
      </ScrollView>
      <View style={{ height: 10 }} />
    </View>
  );
  const render = useCallback(({ item: t, index }: { item: TeamT; index: number }) => (
    <DiscCell t={t} cell={cell} last={index % 4 === 3} sel={t.id === focus} own={dz.has(t.id)} price={dz.catalog[t.id]?.price_gems ?? 0} eq={t.id === p.team} onPress={() => setFocus(t.id)} />
  ), [cell, focus, dz.has, dz.catalog, p.team]);
  return (
    <FlatList data={list} key={'d' + cat} numColumns={4} keyExtractor={t => t.id} renderItem={render} ListHeaderComponent={header}
      contentContainerStyle={{ paddingBottom: bottom + 10 }} columnWrapperStyle={{ paddingHorizontal: 16 }} showsVerticalScrollIndicator={false}
      initialNumToRender={16} maxToRenderPerBatch={12} windowSize={7} removeClippedSubviews />
  );
}

const DiscCell = memo(function DiscCell({ t, cell, last, sel, own, eq, price, onPress }: { t: TeamT; cell: number; last: boolean; sel: boolean; own: boolean; eq: boolean; price: number; onPress: () => void }) {
  const rc = RARITY[rarity(t)].c;
  return (
    <Press onPress={onPress} style={{ width: cell, marginRight: last ? 0 : 8, marginBottom: 8 }} scaleTo={.92}>
      <View style={[s.cell, { height: cell + 20, borderColor: sel ? rc : 'rgba(110,170,255,.16)' }, sel && { backgroundColor: rc + '22' }]}>
        <Img src={TEAM_IMG[teamKey(t)]} style={{ width: cell - 16, height: cell - 16, borderRadius: (cell - 16) / 2, opacity: own ? 1 : .5 }} />
        {eq ? <T s="● فعال" style={{ fontSize: 9, color: C.green, marginTop: 2 }} /> : own ? <T s=" " style={{ fontSize: 9, marginTop: 2 }} /> : (
          <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 2 }}><Img src={UI2.x_gem} style={{ width: 12, height: 12 }} /><T s={price} style={{ fontFamily: F.head, fontSize: 8, color: '#9fd8ff', marginLeft: 2 }} /></View>
        )}
        {!own ? <View style={s.lock}><T s="🔒" style={{ fontSize: 9 }} /></View> : null}
      </View>
    </Press>
  );
});

function DiscHero({ t, color }: { t: TeamT; color: string }) {
  const spin = useSharedValue(0), pop = useSharedValue(1);
  useEffect(() => { spin.value = withRepeat(withTiming(1, { duration: 12000, easing: Easing.linear }), -1, false); }, []);
  useEffect(() => { pop.value = withSequence(withTiming(.75, { duration: 70 }), withSpring(1, { damping: 8, stiffness: 220 })); }, [t.id]);
  const ring = useAnimatedStyle(() => ({ transform: [{ rotate: `${spin.value * 360}deg` }] }));
  const ring2 = useAnimatedStyle(() => ({ transform: [{ rotate: `${-spin.value * 720}deg` }] }));
  const disc = useAnimatedStyle(() => ({ transform: [{ scale: pop.value }] }));
  return (
    <View style={{ height: 230, alignItems: 'center', justifyContent: 'center' }}>
      <Img src={UI.holopad} style={{ position: 'absolute', bottom: 0, width: 240, height: 86, opacity: .9 }} />
      <Pulse size={150} color={color + '55'} />
      <Animated.View style={[{ position: 'absolute', width: 220, height: 220 }, ring]}><Img src={UI2.ring} style={{ width: 220, height: 220, opacity: .75 }} /></Animated.View>
      <Animated.View style={[{ position: 'absolute', width: 184, height: 184, borderRadius: 92, borderWidth: 2, borderColor: color + '88', borderStyle: 'dashed' }, ring2]} />
      <Animated.View style={[s.disc, { borderColor: color, shadowColor: color }, disc]}>
        <Img src={TEAM_IMG[teamKey(t)]} style={{ width: 132, height: 132, borderRadius: 66 }} />
        <LinearGradient colors={['rgba(255,255,255,.4)', 'rgba(255,255,255,0)', 'rgba(255,255,255,0)']} start={{ x: .2, y: 0 }} end={{ x: .7, y: .8 }} style={[StyleSheet.absoluteFill, { borderRadius: 74 }]} />
      </Animated.View>
    </View>
  );
}

// ---------- balls ----------
function Balls({ bottom, toast }: { bottom: number; toast: Toast }) {
  const { p, set } = useStore(); const { width: W } = useWindowDimensions();
  const [fb, setFb] = useState(p.ball);
  const ids = useMemo(() => Array.from({ length: 36 }, (_, i) => i), []);
  const cell = (W - 32 - 3 * 8) / 4;
  const owned = p.ownedBalls.includes(fb), price = ballPrice(fb), eq = p.ball === fb, tr = TRAILS[fb % TRAILS.length].c;
  const act = () => {
    if (owned) { set({ ball: fb }); buzz('success'); toast('توپ انتخاب شد', 'ok'); return; }
    if (p.coins < price) { toast('سکه کافی نداری', 'err'); return; }
    set(q => ({ coins: q.coins - price, ownedBalls: [...q.ownedBalls, fb], ball: fb })); sfx('goal'); buzz('success'); toast('توپ جدید باز شد!', 'ok');
  };
  const header = (
    <View>
      <BallHero idx={fb} />
      <T s={`${BALL_NAMES[fb]}`.toUpperCase()} style={{ fontFamily: F.title, fontSize: 20, textAlign: 'center' }} />
      <View style={{ flexDirection: 'row', justifyContent: 'center', marginTop: 8 }}>{tr.map((c, i) => <View key={i} style={{ width: 28, height: 6, borderRadius: 3, backgroundColor: c, marginHorizontal: 3, shadowColor: c, shadowOpacity: 1, shadowRadius: 6 }} />)}</View>
      <T s="رنگ دنباله‌ی توپ" style={{ fontSize: 10, color: C.dim, textAlign: 'center', marginTop: 4 }} />
      <View style={{ paddingHorizontal: 50, marginTop: 12, marginBottom: 14 }}>
        {eq ? <Btn label="انتخاب‌شده ✓" small colors={G.dark} disabled /> : owned ? <Btn label="انتخاب" small onPress={act} colors={G.green} /> : <Btn label={`خرید · ${price}`} small icon={UI2.c_coin} colors={G.gold} onPress={act} />}
      </View>
    </View>
  );
  return (
    <FlatList data={ids} numColumns={4} keyExtractor={i => 'b' + i} ListHeaderComponent={header} contentContainerStyle={{ paddingBottom: bottom + 10 }} columnWrapperStyle={{ paddingHorizontal: 16 }}
      showsVerticalScrollIndicator={false} initialNumToRender={16} removeClippedSubviews
      renderItem={({ item: i, index }) => {
        const own = p.ownedBalls.includes(i), sel = i === fb, e = p.ball === i;
        return (
          <Press onPress={() => setFb(i)} style={{ width: cell, marginRight: index % 4 === 3 ? 0 : 8, marginBottom: 8 }} scaleTo={.92}>
            <View style={[s.cell, { height: cell + 18, borderColor: sel ? C.green : 'rgba(110,170,255,.16)' }, sel && { backgroundColor: 'rgba(61,255,168,.12)' }]}>
              <Img src={BALL_IMG['b' + i]} style={{ width: cell - 22, height: cell - 22, borderRadius: (cell - 22) / 2, opacity: own ? 1 : .5 }} />
              <T s={e ? '● فعال' : own ? BALL_NAMES[i] : `${ballPrice(i)} ◉`} n={1} style={{ fontSize: 9, color: e ? C.green : own ? C.dim : C.gold, marginTop: 3, fontFamily: own && !e ? F.head : undefined }} />
            </View>
          </Press>
        );
      }} />
  );
}

function BallHero({ idx }: { idx: number }) {
  const spin = useSharedValue(0), bob = useSharedValue(0);
  useEffect(() => {
    spin.value = withRepeat(withTiming(1, { duration: 5000, easing: Easing.linear }), -1, false);
    bob.value = withRepeat(withTiming(1, { duration: 1400, easing: Easing.inOut(Easing.sin) }), -1, true);
  }, []);
  const a = useAnimatedStyle(() => ({ transform: [{ translateY: -bob.value * 14 }, { rotate: `${spin.value * 360}deg` }] }));
  const sh = useAnimatedStyle(() => ({ transform: [{ scaleX: 1 - bob.value * .25 }], opacity: .55 - bob.value * .2 }));
  return (
    <View style={{ height: 220, alignItems: 'center', justifyContent: 'center' }}>
      <Img src={UI.holopad} style={{ position: 'absolute', bottom: 6, width: 230, height: 84 }} />
      <Animated.View style={[{ position: 'absolute', bottom: 40, width: 110, height: 18, borderRadius: 55, backgroundColor: '#000' }, sh]} />
      <Pulse size={130} color="rgba(61,255,216,.35)" />
      <Animated.View style={a}><Img src={BALL_IMG['b' + idx]} style={{ width: 132, height: 132, borderRadius: 66 }} /></Animated.View>
    </View>
  );
}

// ---------- fields ----------
function Fields({ bottom, toast }: { bottom: number; toast: Toast }) {
  const { p, set } = useStore(); const { width: W } = useWindowDimensions();
  const [ff, setFf] = useState(p.field);
  const ids = useMemo(() => FIELDS.map((_, i) => i), []);
  const cell = (W - 32 - 2 * 10) / 3;
  const owned = p.ownedFields.includes(ff), price = fieldPrice(ff), eq = p.field === ff;
  const act = () => {
    if (owned) { set({ field: ff }); buzz('success'); toast('زمین انتخاب شد', 'ok'); return; }
    if (p.coins < price) { toast('سکه کافی نداری', 'err'); return; }
    set(q => ({ coins: q.coins - price, ownedFields: [...q.ownedFields, ff], field: ff })); sfx('goal'); buzz('success'); toast('زمین جدید باز شد!', 'ok');
  };
  const header = (
    <View style={{ alignItems: 'center' }}>
      <View style={s.arena}>
        <Img src={FIELD_THUMB[FIELDS[ff].id]} style={{ width: 160, height: 214, borderRadius: 16 }} fit="cover" />
        <LinearGradient colors={['rgba(255,255,255,.2)', 'transparent', 'rgba(0,0,0,.3)']} style={[StyleSheet.absoluteFill, { borderRadius: 18 }]} />
      </View>
      <T s={FIELDS[ff].name.toUpperCase()} style={{ fontFamily: F.title, fontSize: 20, marginTop: 10 }} />
      <View style={{ alignSelf: 'stretch', paddingHorizontal: 50, marginTop: 12, marginBottom: 14 }}>
        {eq ? <Btn label="انتخاب‌شده ✓" small colors={G.dark} disabled /> : owned ? <Btn label="انتخاب" small onPress={act} colors={G.green} /> : <Btn label={`خرید · ${price}`} small icon={UI2.c_coin} colors={G.gold} onPress={act} />}
      </View>
    </View>
  );
  return (
    <FlatList data={ids} numColumns={3} keyExtractor={i => 'f' + i} ListHeaderComponent={header} contentContainerStyle={{ paddingBottom: bottom + 10 }} columnWrapperStyle={{ paddingHorizontal: 16 }}
      showsVerticalScrollIndicator={false} initialNumToRender={9} removeClippedSubviews
      renderItem={({ item: i, index }) => {
        const own = p.ownedFields.includes(i), sel = i === ff, e = p.field === i;
        return (
          <Press onPress={() => setFf(i)} style={{ width: cell, marginRight: index % 3 === 2 ? 0 : 10, marginBottom: 10 }} scaleTo={.94}>
            <View style={[s.cell, { paddingVertical: 8, borderColor: sel ? C.cyan : 'rgba(110,170,255,.16)' }, sel && { backgroundColor: 'rgba(79,227,255,.12)' }]}>
              <Img src={FIELD_THUMB[FIELDS[i].id]} style={{ width: cell - 16, height: (cell - 16) * 1.33, borderRadius: 10, opacity: own ? 1 : .5 }} fit="cover" />
              <T s={e ? '● فعال' : own ? FIELDS[i].name : `${fieldPrice(i)} ◉`} n={1} style={{ fontSize: 10, color: e ? C.green : own ? C.dim : C.gold, marginTop: 4, fontFamily: own && !e ? F.bold : undefined }} />
            </View>
          </Press>
        );
      }} />
  );
}

// ---------- formation ----------
function Formation({ bottom }: { bottom: number }) {
  const { p, set } = useStore(); const { width: W } = useWindowDimensions();
  const me = teamById(p.team);
  const fw = Math.min(W - 64, 300), fh = fw * 1.35;
  const pts = slots(p.form);
  return (
    <ScrollView contentContainerStyle={{ paddingBottom: bottom + 10, alignItems: 'center' }} showsVerticalScrollIndicator={false}>
      <View style={[s.pitch, { width: fw, height: fh }]}>
        <Img src={FIELD_THUMB[FIELDS[p.field].id]} style={StyleSheet.absoluteFill} fit="cover" />
        <View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(2,6,20,.35)' }]} />
        <View style={[s.mid, { top: fh / 2 }]} />
        <View style={[s.circle, { left: fw / 2 - 30, top: fh / 2 - 30 }]} />
        {pts.map(([nx, ny], i) => <Slot key={p.form + '-' + i} x={18 + nx * (fw - 36)} y={fh - ny * fh * 1.9} img={TEAM_IMG[teamKey(me)]} delay={i * 50} />)}
      </View>
      <T s={`${FORMS[p.form][0]} · ${FORMS[p.form][1]}`} style={{ fontFamily: F.title, fontSize: 18, marginTop: 12 }} />
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', justifyContent: 'center', paddingHorizontal: 12, marginTop: 10 }}>
        {FORMS.map((f, i) => (
          <Press key={f[0]} onPress={() => set({ form: i })} style={[s.form, p.form === i && { borderColor: C.cyan, backgroundColor: 'rgba(79,227,255,.15)' }]}>
            <T s={f[0]} style={{ fontFamily: F.head, fontSize: 14, color: p.form === i ? '#fff' : C.dim }} />
            <T s={f[1]} style={{ fontFamily: F.body, fontSize: 10, color: C.dim2 }} />
          </Press>
        ))}
      </View>
    </ScrollView>
  );
}

function Slot({ x, y, img, delay }: { x: number; y: number; img: any; delay: number }) {
  const sc = useSharedValue(0);
  useEffect(() => { const t = setTimeout(() => { sc.value = withSpring(1, { damping: 10, stiffness: 200 }); }, delay); return () => clearTimeout(t); }, []);
  const a = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));
  return (
    <Animated.View style={[{ position: 'absolute', left: x - 20, top: y - 20, width: 40, height: 40, borderRadius: 20, borderWidth: 2, borderColor: C.cyan, backgroundColor: '#050816', alignItems: 'center', justifyContent: 'center', shadowColor: C.cyan, shadowOpacity: .9, shadowRadius: 8 }, a]}>
      <Img src={img} style={{ width: 34, height: 34, borderRadius: 17 }} />
    </Animated.View>
  );
}

const s = StyleSheet.create({
  disc: { width: 148, height: 148, borderRadius: 74, borderWidth: 4, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816', shadowOpacity: .9, shadowRadius: 22, shadowOffset: { width: 0, height: 0 }, elevation: 12 },
  rar: { paddingHorizontal: 12, height: 22, borderRadius: 11, borderWidth: 1, justifyContent: 'center' },
  cell: { borderRadius: 16, borderWidth: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(8,12,34,.78)' },
  lock: { position: 'absolute', top: 4, right: 4 },
  arena: { marginTop: 8, borderWidth: 2, borderColor: C.cyan, borderRadius: 18, padding: 3, shadowColor: C.cyan, shadowOpacity: .7, shadowRadius: 20, shadowOffset: { width: 0, height: 0 }, elevation: 10, backgroundColor: '#050816' },
  pitch: { marginTop: 8, borderRadius: 20, overflow: 'hidden', borderWidth: 2, borderColor: 'rgba(79,227,255,.55)' },
  mid: { position: 'absolute', left: 0, right: 0, height: 1, backgroundColor: 'rgba(255,255,255,.35)' },
  circle: { position: 'absolute', width: 60, height: 60, borderRadius: 30, borderWidth: 1, borderColor: 'rgba(255,255,255,.35)' },
  form: { width: 92, alignItems: 'center', paddingVertical: 10, margin: 4, borderRadius: 16, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(8,12,34,.8)' },
});
void fa;
