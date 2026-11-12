import React, { memo, useEffect, useMemo, useState } from 'react';
import { ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { TEAM_IMG, UI2 } from '../game/assets';
import { TEAMS } from '../game/data';
import { CHEST_EVERY, ChestPrize, Item, allItems, dailyDeals, grant } from '../game/meta';
import { teamKey } from '../game/util';
import { useStore } from '../store';
import { Btn, Enter, Float, Img, Panel, Press, Pulse, Segment, T, Title } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { useDiscs, useBuyDisc } from '../net/discs';
import { useAuth } from '../net/auth';
import { StatBars, discImg } from '../online/ui';
import { buzz, sfx } from '../sound';

type Toast = (m: string, k?: string) => void;
const RC = ['#8ea3d6', '#4fe3ff', '#b46bff', '#ffd257'];

function Shop({ top, bottom, toast, onChest }: { top: number; bottom: number; toast: Toast; onChest: (premium: boolean) => void }) {
  const { p, set } = useStore(); const { width: W } = useWindowDimensions();
  const [kind, setKind] = useState<'team' | 'ball' | 'field'>('team');
  const items = useMemo(() => allItems(p), [p.ownedTeams, p.ownedBalls, p.ownedFields]);
  const deals = useMemo(() => dailyDeals(p), [p.ownedTeams, p.ownedBalls, p.ownedFields]);
  const legends = TEAMS.filter(t => t.cat === 'leg');
  const now = Date.now(), freeIn = Math.max(0, p.lastChest + CHEST_EVERY - now);
  const buy = (it: Item) => {
    if (p.coins < it.price) { toast('سکه کافی نداری', 'err'); buzz('medium'); return; }
    set(q => ({ coins: q.coins - it.price, ...grant(it)(q) })); sfx('goal'); buzz('success'); toast(`${it.name} باز شد!`, 'ok');
  };
  const dz = useDiscs(); const auth = useAuth();
  const buyDisc = useBuyDisc(toast, id => { set({ team: id }); sfx('win'); buzz('success'); });
  const gemDiscs = useMemo(() => Object.values(dz.catalog).filter(d => d.price_gems > 0 && !dz.owned.has(d.id)).sort((a, b) => a.price_gems - b.price_gems), [dz.catalog, dz.owned]);
  const cell = (W - 32 - 16) / 3;
  const list = items.filter(i => i.kind === kind);
  const legW = Math.min(W * .42, 180);
  return (
    <ScrollView contentContainerStyle={{ paddingTop: top, paddingBottom: bottom + 10 }} showsVerticalScrollIndicator={false}>
      {/* legends banner */}
      <Enter i={0} style={{ paddingHorizontal: 16 }}>
        <View style={s.banner}>
          <LinearGradient colors={['#3b1a00', '#1a0d3a', '#070a22']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
          <Img src={UI2.screens} style={{ position: 'absolute', right: -30, top: -10, width: 260, height: 180, opacity: .25 }} />
          <View style={{ flex: 1, padding: 14, alignItems: 'flex-end' }}>
            <T s="LEGENDARY DISCS" style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 3, color: C.gold }} />
            <T s="دیسک‌های افسانه‌ای" style={{ fontFamily: F.title, fontSize: 19, marginTop: 2 }} />
            <T s="قدرت و دقت بالا · با الماس" style={{ fontSize: 11, color: '#e8d7ad', marginTop: 4 }} />
            <View style={s.tag}><T s="محدود" style={{ fontSize: 11, color: '#1b0e00', fontFamily: F.bold }} /></View>
          </View>
          <Float amp={6}><Img src={TEAM_IMG[teamKey(legends[(Math.floor(now / 86400000)) % legends.length])]} style={{ width: legW * .8, height: legW * .8, margin: 10 }} /></Float>
        </View>
      </Enter>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12, paddingTop: 10 }}>
        {legends.map((t, i) => {
          const own = dz.has(t.id), it = { name: t.name, price: dz.catalog[t.id]?.price_gems ?? 0, img: TEAM_IMG[teamKey(t)] };
          return (
            <Enter key={t.id} i={i}>
              <Press onPress={() => !own && buyDisc(t.id, t.name)} style={[s.leg, own && { opacity: .6 }]}>
                <LinearGradient colors={['rgba(255,210,87,.25)', 'rgba(10,12,34,.9)']} style={StyleSheet.absoluteFill} />
                <Img src={it.img} style={{ width: 92, height: 92 }} />
                <T s={t.name} n={1} style={{ fontFamily: F.bold, fontSize: 11, marginTop: 4 }} />
                {own ? <T s="✓ داری" style={{ fontSize: 11, color: C.green, marginTop: 3 }} /> : <PriceTag v={it.price} gem />}
              </Press>
            </Enter>
          );
        })}
      </ScrollView>

      {/* chests */}
      <Title s="صندوقچه‌ها" en="SUPPLY CHESTS" accent={C.violet} />
      <View style={{ flexDirection: 'row-reverse', paddingHorizontal: 12 }}>
        <Enter i={1} style={{ flex: 1, padding: 4 }}>
          <Panel style={{ alignItems: 'center', padding: 12 }} accent={C.cyan} glow={!freeIn}>
            <Shake on={!freeIn}><Img src={UI2.c_chest} style={{ width: 96, height: 96 }} /></Shake>
            <T s="صندوقچه‌ی رایگان" style={{ fontFamily: F.bold, fontSize: 13, marginTop: 2 }} />
            <T s="هر ۴ ساعت" style={{ fontSize: 10, color: C.dim }} />
            <View style={{ alignSelf: 'stretch', marginTop: 8 }}>
              <Btn small label={freeIn ? fmt(freeIn) : 'باز کن'} disabled={!!freeIn} colors={G.primary} onPress={() => onChest(false)} />
            </View>
          </Panel>
        </Enter>
        <Enter i={2} style={{ flex: 1, padding: 4 }}>
          <Panel style={{ alignItems: 'center', padding: 12 }} accent={C.gold} glow>
            <Shake on><Img src={UI2.x_chest} style={{ width: 96, height: 96 }} /></Shake>
            <T s="صندوقچه‌ی سلطنتی" style={{ fontFamily: F.bold, fontSize: 13, marginTop: 2 }} />
            <T s="آیتم کمیاب تضمینی‌تر" style={{ fontSize: 10, color: C.dim }} />
            <View style={{ alignSelf: 'stretch', marginTop: 8 }}>
              <Btn small label="۶۰۰ سکه" icon={UI2.c_coin} colors={G.violet} onPress={() => { if (p.coins < 600) { toast('۶۰۰ سکه لازمه', 'err'); return; } onChest(true); }} />
            </View>
          </Panel>
        </Enter>
      </View>

      {/* deals */}
      {deals.length ? <Title s="پیشنهاد امروز" en="DAILY DEALS · -30%" accent={C.green} /> : null}
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', paddingHorizontal: 16, justifyContent: 'space-between' }}>
        {deals.map((it, i) => (
          <Enter key={it.kind + it.id} i={i} style={{ width: (W - 32 - 8) / 2, marginBottom: 8 }}>
            <Press onPress={() => buy(it)}>
              <Panel style={{ flexDirection: 'row-reverse', alignItems: 'center', padding: 10 }} accent={RC[it.rar]}>
                <Img src={it.img} style={it.kind === 'field' ? { width: 40, height: 54, borderRadius: 6 } : { width: 54, height: 54, borderRadius: 27 }} fit={it.kind === 'field' ? 'cover' : 'contain'} />
                <View style={{ flex: 1, marginRight: 8, alignItems: 'flex-end' }}>
                  <T s={it.name} n={1} style={{ fontFamily: F.bold, fontSize: 12 }} />
                  <View style={s.off}><T s="-۳۰٪" style={{ fontSize: 10, color: '#03140c', fontFamily: F.bold }} /></View>
                  <PriceTag v={it.price} />
                </View>
              </Panel>
            </Press>
          </Enter>
        ))}
      </View>

      {/* catalogue */}
      <Title s="همه‌ی تجهیزات" en="CATALOGUE" />
      <View style={{ paddingHorizontal: 16, marginBottom: 10 }}>
        <Segment value={kind} onChange={setKind} items={[['team', 'دیسک'], ['ball', 'توپ'], ['field', 'زمین']]} accent={C.gold} />
      </View>
      {kind === 'team' ? (
        <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', paddingHorizontal: 16 }}>
          {!auth.profile ? <T s="قیمت دیسک‌ها به الماس است؛ با ورود آنلاین (حتی مهمان) ۱۵۰ الماس هدیه می‌گیری." style={{ fontSize: 11, color: C.dim, textAlign: 'right', marginBottom: 8, width: '100%' }} /> : null}
          {gemDiscs.slice(0, 60).map((d, i) => (
            <Press key={d.id} onPress={() => buyDisc(d.id, d.name)} style={{ width: cell, marginLeft: i % 3 === 2 ? 0 : 8, marginBottom: 8 }} scaleTo={.93}>
              <View style={[s.card, { borderColor: RC[d.price_gems >= 250 ? 3 : d.price_gems >= 180 ? 2 : 1] + '66', paddingHorizontal: 6 }]}>
                <Img src={discImg(d.id)} style={{ width: cell * .6, height: cell * .6, borderRadius: cell }} />
                <T s={d.name} n={1} style={{ fontFamily: F.bold, fontSize: 10, marginTop: 4 }} />
                <StatBars power={d.power} accuracy={d.accuracy} compact />
                <PriceTag v={d.price_gems} gem />
              </View>
            </Press>
          ))}
        </View>
      ) : null}
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', paddingHorizontal: 16 }}>
        {list.slice(0, 60).map((it, i) => (
          <Press key={it.kind + it.id} onPress={() => buy(it)} style={{ width: cell, marginLeft: i % 3 === 2 ? 0 : 8, marginBottom: 8 }} scaleTo={.93}>
            <View style={[s.card, { borderColor: RC[it.rar] + '66' }]}>
              <LinearGradient colors={[RC[it.rar] + '30', 'rgba(8,12,34,.2)']} style={StyleSheet.absoluteFill} />
              <Img src={it.img} style={it.kind === 'field' ? { width: cell * .52, height: cell * .7, borderRadius: 6 } : { width: cell * .64, height: cell * .64, borderRadius: cell }} fit={it.kind === 'field' ? 'cover' : 'contain'} />
              <T s={it.name} n={1} style={{ fontFamily: F.bold, fontSize: 10, marginTop: 5 }} />
              <PriceTag v={it.price} />
            </View>
          </Press>
        ))}
      </View>
      {!list.length && kind !== 'team' ? <T s="همه‌چیز این بخش رو داری، اسطوره!" style={{ textAlign: 'center', color: C.dim, marginTop: 10 }} /> : null}
    </ScrollView>
  );
}
export default memo(Shop);

const fmt = (ms: number) => { const m = Math.ceil(ms / 60000), h = Math.floor(m / 60); return h ? `${fa(h)}س ${fa(m % 60)}د` : `${fa(m)} دقیقه`; };

function PriceTag({ v, gem }: { v: number; gem?: boolean }) {
  return (
    <View style={s.price}><Img src={gem ? UI2.x_gem : UI2.c_coin} style={{ width: 16, height: 16 }} /><T s={v} style={{ fontFamily: F.head, fontSize: 10, color: gem ? '#9fd8ff' : C.gold, marginLeft: 3 }} /></View>
  );
}

function Shake({ on, children }: { on: boolean; children: React.ReactNode }) {
  const r = useSharedValue(0);
  useEffect(() => {
    if (on) r.value = withRepeat(withSequence(withTiming(1, { duration: 80 }), withTiming(-1, { duration: 80 }), withTiming(1, { duration: 80 }), withTiming(0, { duration: 80 }), withDelay(1800, withTiming(0, { duration: 10 }))), -1, false);
    else r.value = 0;
  }, [on]);
  const a = useAnimatedStyle(() => ({ transform: [{ rotate: `${r.value * 6}deg` }] }));
  return <Animated.View style={a}>{children}</Animated.View>;
}

// ---------- chest opening (shown by App in a Modal) ----------
export function ChestOpen({ prize, premium, onDone }: { prize: ChestPrize; premium: boolean; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const shake = useSharedValue(0), pop = useSharedValue(0), rays = useSharedValue(0);
  useEffect(() => {
    shake.value = withSequence(withRepeat(withSequence(withTiming(1, { duration: 70 }), withTiming(-1, { duration: 70 })), 6, true), withTiming(0, { duration: 60 }));
    const t = setTimeout(() => { setOpen(true); sfx('goal'); buzz('heavy'); pop.value = withSpring(1, { damping: 9, stiffness: 160 }); }, 1000);
    rays.value = withRepeat(withTiming(1, { duration: 9000, easing: Easing.linear }), -1, false);
    return () => clearTimeout(t);
  }, []);
  const ch = useAnimatedStyle(() => ({ transform: [{ rotate: `${shake.value * 8}deg` }, { scale: 1 + Math.abs(shake.value) * .05 }] }));
  const pr = useAnimatedStyle(() => ({ opacity: pop.value, transform: [{ scale: .3 + pop.value * .7 }, { translateY: (1 - pop.value) * 40 }] }));
  const ry = useAnimatedStyle(() => ({ transform: [{ rotate: `${rays.value * 360}deg` }] }));
  const it = prize.item;
  return (
    <View style={{ alignItems: 'center', padding: 22 }}>
      <T s={premium ? 'صندوقچه‌ی سلطنتی' : 'صندوقچه‌ی رایگان'} style={{ fontFamily: F.title, fontSize: 20 }} />
      <View style={{ height: 220, width: '100%', alignItems: 'center', justifyContent: 'center' }}>
        <Animated.View style={[{ position: 'absolute' }, ry]}><Img src={UI2.ring} style={{ width: 220, height: 220, opacity: open ? .8 : .3 }} /></Animated.View>
        <Pulse size={140} color={premium ? 'rgba(255,210,87,.4)' : 'rgba(79,227,255,.4)'} />
        {!open ? <Animated.View style={ch}><Img src={premium ? UI2.x_chest : UI2.c_chest} style={{ width: 170, height: 170 }} /></Animated.View> : (
          <Animated.View style={[{ alignItems: 'center' }, pr]}>
            {it ? <Img src={it.img} style={it.kind === 'field' ? { width: 110, height: 150, borderRadius: 12 } : { width: 150, height: 150, borderRadius: 75 }} fit={it.kind === 'field' ? 'cover' : 'contain'} /> : <Img src={UI2.x_coins} style={{ width: 150, height: 150 }} />}
          </Animated.View>
        )}
      </View>
      {open ? (
        <Animated.View style={[{ alignItems: 'center', alignSelf: 'stretch' }, pr]}>
          {it ? <T s={it.name} style={{ fontFamily: F.title, fontSize: 18, color: RC[it.rar] }} /> : null}
          <T s={[it ? 'آیتم جدید باز شد!' : '', prize.coins ? `+${fa(prize.coins)} سکه` : '', prize.gems ? `+${fa(prize.gems)} الماس` : ''].filter(Boolean).join(' · ')} style={{ color: C.dim, marginTop: 4, textAlign: 'center' }} />
          <View style={{ alignSelf: 'stretch', marginTop: 16 }}><Btn label="عالیه!" onPress={onDone} colors={G.gold} /></View>
        </Animated.View>
      ) : <T s="در حال باز شدن..." style={{ color: C.dim }} />}
    </View>
  );
}

const s = StyleSheet.create({
  banner: { height: 150, borderRadius: 24, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: 'rgba(255,210,87,.5)', shadowColor: C.gold, shadowOpacity: .45, shadowRadius: 18, shadowOffset: { width: 0, height: 0 }, elevation: 10 },
  tag: { marginTop: 8, paddingHorizontal: 10, height: 22, borderRadius: 11, backgroundColor: C.gold, justifyContent: 'center' },
  leg: { width: 116, height: 150, marginHorizontal: 4, borderRadius: 20, borderWidth: 1, borderColor: 'rgba(255,210,87,.4)', overflow: 'hidden', alignItems: 'center', justifyContent: 'center', backgroundColor: '#0a0d26' },
  price: { flexDirection: 'row', alignItems: 'center', marginTop: 5, paddingHorizontal: 8, height: 22, borderRadius: 11, backgroundColor: 'rgba(255,210,87,.14)', borderWidth: 1, borderColor: 'rgba(255,210,87,.3)' },
  off: { marginTop: 3, paddingHorizontal: 6, height: 16, borderRadius: 8, backgroundColor: C.green, justifyContent: 'center' },
  best: { position: 'absolute', top: 6, left: 6, paddingHorizontal: 6, height: 16, borderRadius: 8, backgroundColor: C.gold, justifyContent: 'center', zIndex: 2 },
  card: { borderRadius: 16, borderWidth: 1, overflow: 'hidden', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 4, backgroundColor: 'rgba(8,12,34,.8)' },
});
