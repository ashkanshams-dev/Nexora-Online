import React, { useCallback, useEffect, useRef, useState } from 'react';
import { BackHandler, StyleSheet, View } from 'react-native';
import Animated, { Easing, FadeIn, FadeOut, useAnimatedStyle, useSharedValue, withDelay, withSequence, withSpring, withTiming } from 'react-native-reanimated';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFonts, Orbitron_700Bold, Orbitron_900Black } from '@expo-google-fonts/orbitron';
import { Exo2_600SemiBold, Exo2_800ExtraBold } from '@expo-google-fonts/exo-2';
import { Vazirmatn_500Medium, Vazirmatn_800ExtraBold } from '@expo-google-fonts/vazirmatn';
import { StoreProvider, level, useStore } from './src/store';
import { C, F, G, fa } from './src/ui/theme';
import { Btn, Img, T } from './src/ui/kit';
import { UI2 } from './src/game/assets';
import { TEAMS } from './src/game/data';
import { CHEST_EVERY, ChestPrize, DAILY, grant, rollChest } from './src/game/meta';
import { initSound, setAudioPrefs, setAudioScene, sfx, buzz } from './src/sound';
import Space from './src/ui/Space';
import { Hud, Modal, Sheet, SheetHandle, TabBar, TAB_H, Tab } from './src/ui/Chrome';
import Intro from './src/screens/Intro';
import Home from './src/screens/Home';
import Play from './src/screens/Play';
import TeamScreen from './src/screens/Team';
import Shop, { ChestOpen } from './src/screens/Shop';
import Profile from './src/screens/Profile';
import Settings from './src/screens/Settings';
import Match, { MatchResult } from './src/screens/Match';
import Result, { Reward } from './src/screens/Result';
import Setup, { Launch, Mode, buildLaunch } from './src/screens/Setup';
import { AuthProvider, useAuth } from './src/net/auth';
import { DiscProvider } from './src/net/discs';
import { rpc } from './src/net/supabase';
import { NavCtx, OnlineEntry } from './src/nav';
import OnlineRoot from './src/online/OnlineRoot';
import { RecoveryModal } from './src/screens/Account';
import Social from './src/social/Social';
import Chat from './src/social/Chat';
import PublicProfile from './src/social/PublicProfile';
import ClubPage from './src/social/ClubPage';
import { Header } from './src/online/ui';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { OracleProvider, prefetchOracle, useOracle } from './src/oracle/Oracle';

type Route = 'tabs' | 'match' | 'result' | 'online';
type Overlay = { k: 'profile'; id: string } | { k: 'chat'; id: string } | { k: 'club'; id: string } | { k: 'team' };
const DAY = 86400000;
const MULT: Record<string, number> = { quick: 1, cup: 2, galaxy: 3, train: .3, local: 0 };

function Shell() {
  const [toastM, setToastM] = useState<{ m: string; k: string; id: number } | null>(null);
  const tA = useSharedValue(0);
  const toast = useCallback((m: string, k = 'info') => {
    setToastM({ m, k, id: Date.now() });
    tA.value = withSequence(withSpring(1, { damping: 14 }), withDelay(1700, withTiming(0, { duration: 250 })));
  }, []);
  const ins = useSafeAreaInsets();
  const toastSt = useAnimatedStyle(() => ({ opacity: tA.value, transform: [{ translateY: -20 + tA.value * 20 }, { scale: .9 + tA.value * .1 }] }));
  return (
    <AuthProvider toast={toast}>
      <DiscProvider>
        <ShellInner toast={toast} />
        {toastM ? (
          <Animated.View pointerEvents="none" style={[st.toast, { top: ins.top + 64 }, toastSt]}>
            <View style={[st.toastIn, { borderColor: toastM.k === 'err' ? C.red : toastM.k === 'ok' ? C.green : C.cyan }]}>
              <Img src={toastM.k === 'err' ? UI2.c_bell : toastM.k === 'ok' ? UI2.x_star : UI2.c_mega} style={{ width: 26, height: 26, marginRight: 6 }} />
              <T s={toastM.m} style={{ fontFamily: F.bold, fontSize: 14, flexShrink: 1 }} />
            </View>
          </Animated.View>
        ) : null}
      </DiscProvider>
    </AuthProvider>
  );
}

// lets the shell (which sits above the Oracle provider) forward toasts to Oracle reactions
function OracleBridge({ r }: { r: React.MutableRefObject<ReturnType<typeof useOracle> | null> }) { r.current = useOracle(); return null; }

function ShellInner({ toast: rawToast }: { toast: (m: string, k?: string) => void }) {
  const oracleRef = useRef<ReturnType<typeof useOracle> | null>(null);
  const toast = useCallback((m: string, k = 'info') => {
    rawToast(m, k);
    const o = oracleRef.current; if (!o) return;
    if (k === 'err') { if (/الماس/.test(m)) o.react('nogems'); else o.react('error', m); }
    else if (k === 'ok') { if (/باز شد|خرید/.test(m)) o.react('purchase'); else if (/الماس|XP|سکه|جایزه/.test(m)) o.react('reward', m); }
  }, [rawToast]);
  const ins = useSafeAreaInsets();
  const auth = useAuth();
  const [onlineEntry, setOnlineEntry] = useState<OnlineEntry>('hub');
  const [onlineQuick, setOnlineQuick] = useState<'1v1' | '2v2' | '3v3' | null>(null);
  useEffect(() => { prefetchOracle(); }, []);
  const { p, set, ready } = useStore();
  const [route, setRoute] = useState<Route>('tabs');
  const [tab, setTab] = useState<Tab>('home');
  const [intro, setIntro] = useState(true);
  const [sheet, setSheet] = useState<null | { k: 'setup'; mode: Mode } | { k: 'settings' }>(null);
  const [modal, setModal] = useState<null | { k: 'daily' } | { k: 'chest'; prize: ChestPrize; premium: boolean }>(null);
  const [launch, setLaunch] = useState<Launch | null>(null);
  const [result, setResult] = useState<{ r: MatchResult; reward: Reward | null; cup?: { stage: number; won: boolean; champion: boolean }; levelUp?: number } | null>(null);
  const [matchKey, setMatchKey] = useState(0);
  // full-screen overlays that can open on top of anything (profile, chat, club, team)
  const [overlays, setOverlays] = useState<Overlay[]>([]);
  const pushOverlay = useCallback((o: Overlay) => setOverlays(s => {
    const k = (x: Overlay) => x.k + ('id' in x ? x.id : '');
    return [...s.filter(x => k(x) !== k(o)), o].slice(-6);
  }), []);
  const popOverlay = useCallback(() => setOverlays(s => s.slice(0, -1)), []);
  const sheetRef = useRef<SheetHandle>(null);
  const veil = useSharedValue(0);

  useEffect(() => { initSound(); }, []);
  useEffect(() => { setAudioPrefs({ sound: p.sound, music: p.music, haptics: p.haptics, volume: p.volume }); }, [p.sound, p.music, p.haptics, p.volume]);
  // online area drives its own scene (lobby = ducked, match = off); everything else is menu / match
  useEffect(() => { if (route !== 'online') setAudioScene(route === 'match' ? 'match' : 'menu'); }, [route]);


  // cross-fade through a dark veil between tabs / match / result
  const transition = (fn: () => void) => {
    veil.value = withTiming(1, { duration: 170, easing: Easing.in(Easing.quad) });
    setTimeout(() => { fn(); veil.value = withTiming(0, { duration: 340, easing: Easing.out(Easing.cubic) }); }, 180);
  };
  const goHome = () => transition(() => { setRoute('tabs'); setTab('home'); });

  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (overlays.length && !sheet && !modal) { popOverlay(); return true; }
      if (route === 'online') return false; // OnlineRoot handles back itself
      if (route === 'result') { goHome(); return true; }
      if (route === 'tabs' && tab !== 'home' && !sheet && !modal) { setTab('home'); return true; }
      return false;
    });
    return () => sub.remove();
  });

  const startMatch = (l: Launch) => { setLaunch(l); setMatchKey(k => k + 1); transition(() => { setSheet(null); setRoute('match'); }); };
  const onFinish = (r: MatchResult) => {
    const l = launch!; let reward: Reward | null = null; let cup: { stage: number; won: boolean; champion: boolean } | undefined; let levelUp: number | undefined;
    const [a, b] = r.score, win = a > b, draw = a === b;
    if (r.ai) {
      const mult = [1, 1.5, 2.2][r.aiLvl] * (MULT[l.mode] ?? 1);
      if (l.mode === 'cup') { const st = l.stage || 0; cup = { stage: st, won: win, champion: win && st >= 2 }; }
      reward = { coins: Math.round((win ? 60 : draw ? 25 : 12) * mult + a * 5), xp: Math.round((win ? 50 : 20) * Math.max(.3, mult)), trophies: l.mode === 'train' ? 0 : win ? Math.round(20 * mult) : draw ? 0 : -8, gems: 0 };
      if (cup?.champion) reward.coins += 400;
      const before = level(p.xp).level, after = level(p.xp + reward.xp).level; if (after > before) levelUp = after;
      const rw = reward;
      set(q => {
        const ws = win ? q.winStreak + 1 : 0;
        return {
          coins: q.coins + rw.coins + (levelUp ? 100 : 0), gems: q.gems + rw.gems, xp: q.xp + rw.xp, trophies: Math.max(0, q.trophies + rw.trophies), played: q.played + 1,
          wins: q.wins + (win ? 1 : 0), losses: q.losses + (!win && !draw ? 1 : 0), draws: q.draws + (draw ? 1 : 0), goalsFor: q.goalsFor + a, goalsAgainst: q.goalsAgainst + b,
          winStreak: ws, bestStreak: Math.max(q.bestStreak, ws), cupsWon: q.cupsWon + (cup?.champion ? 1 : 0),
        };
      });
      if (win) buzz('success');
      // offline bot wins feed the server-side "beat the bot" daily challenge
      if (auth.uid && l.mode !== 'train') rpc('report_offline', { p_won: win }).catch(() => {});
    }
    setResult({ r, reward, cup, levelUp }); transition(() => setRoute('result'));
  };
  const nextCup = () => {
    const l = launch!, st = (l.stage || 0) + 1, pool = TEAMS.filter(t => t.cat === 'club' || t.cat === 'nat' || t.cat === 'elite');
    startMatch(buildLaunch('cup', p, { lvl: 1, rule: 'g3', tt: p.turnTime, opp: pool[Math.floor(Math.random() * pool.length)], stage: st }));
  };

  const dailyReady = Date.now() - p.lastDaily > DAY;
  const chestReady = Date.now() - p.lastChest > CHEST_EVERY;
  const claimDaily = () => {
    if (!dailyReady) return;
    const streak = Date.now() - p.lastDaily < 2 * DAY ? (p.streak % 7) + 1 : 1, rw = DAILY[streak - 1];
    set({ lastDaily: Date.now(), streak, coins: p.coins + rw.coins, gems: p.gems + rw.gems }); sfx('goal'); buzz('success');
    toast(`+${fa(rw.coins)} سکه${rw.gems ? ` · +${fa(rw.gems)} الماس` : ''}`, 'ok'); setModal(null);
  };
  const openChest = (premium: boolean) => {
    if (!premium && !chestReady) { toast('صندوقچه‌ی رایگان هنوز آماده نیست', 'info'); return; }
    if (premium && p.coins < 600) { toast('۶۰۰ سکه لازمه', 'err'); return; }
    const prize = rollChest(p, premium);
    set(q => ({ ...(prize.item ? grant(prize.item)(q) : {}), coins: q.coins + prize.coins - (premium ? 600 : 0), lastChest: premium ? q.lastChest : Date.now(), chests: q.chests + 1 }));
    setModal({ k: 'chest', prize, premium });
  };
  const openMode = useCallback((m: Mode) => setSheet({ k: 'setup', mode: m }), []);
  const openOnline = useCallback((e: OnlineEntry = 'hub', quick?: '1v1' | '2v2' | '3v3') => { setOnlineEntry(e); setOnlineQuick(quick || null); transition(() => { setSheet(null); setOverlays([]); setRoute('online'); }); }, []);
  const oracleActions = React.useMemo(() => ({
    goTab: (t: Tab) => { setOverlays([]); setRoute('tabs'); setTab(t); },
    openOnline: (e?: OnlineEntry, q?: '1v1' | '2v2' | '3v3') => openOnline(e || 'hub', q),
    openSettings: () => setSheet({ k: 'settings' }),
    openTeam: () => pushOverlay({ k: 'team' }),
  }), [openOnline, pushOverlay]);
  const nav = React.useMemo(() => ({
    toast, openOnline,
    openProfile: (id: string) => pushOverlay({ k: 'profile', id }),
    openChat: (id: string) => pushOverlay({ k: 'chat', id }),
    openClub: (id: string) => pushOverlay({ k: 'club', id }),
    openTeam: () => pushOverlay({ k: 'team' }),
  }), [toast, openOnline, pushOverlay]);
  const goTab = useCallback((t: Tab | 'team') => { if (t === 'team') pushOverlay({ k: 'team' }); else setTab(t); }, [pushOverlay]);

  const veilSt = useAnimatedStyle(() => ({ opacity: veil.value }));
  if (!ready) return <View style={{ flex: 1, backgroundColor: C.bg }} />;
  const out = result ? (result.r.score[0] > result.r.score[1] ? 'win' : result.r.score[0] < result.r.score[1] ? 'lose' : 'system') : 'base';
  const top = ins.top + 62, bottom = TAB_H + Math.max(10, ins.bottom) + 6;
  const hq = p.quality === 'high';

  return (
    <NavCtx.Provider value={nav}>
    <OracleProvider actions={oracleActions} tabsVisible={route === 'tabs' && !sheet && !modal && !overlays.length && !intro && ready}>
    <OracleBridge r={oracleRef} />
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      <StatusBar style="light" hidden={route === 'match'} />
      {route === 'tabs' ? (
        <View style={{ flex: 1 }}>
          <Space theme={tab === 'home' ? 'stadium' : tab === 'play' ? 'holo' : 'base'} dim={tab === 'home' || tab === 'play' ? 0 : .15} stars={hq} />
          <Animated.View key={tab} entering={FadeIn.duration(240)} exiting={FadeOut.duration(120)} style={{ flex: 1 }}>
            {tab === 'home' ? <Home top={top} bottom={bottom} onOnline={openOnline} onMode={openMode} onTab={goTab} onDaily={() => setModal({ k: 'daily' })} onSettings={() => setSheet({ k: 'settings' })} onChest={() => openChest(false)} dailyReady={dailyReady} chestReady={chestReady} />
              : tab === 'play' ? <Play top={top} bottom={bottom} onMode={openMode} onOnline={openOnline} />
                : tab === 'social' ? <Social top={top} bottom={bottom} toast={toast} />
                  : tab === 'shop' ? <Shop top={top} bottom={bottom} toast={toast} onChest={openChest} />
                    : <Profile top={top} bottom={bottom} toast={toast} />}
          </Animated.View>
          <Hud onProfile={() => setTab('profile')} onSettings={() => setSheet({ k: 'settings' })} onDaily={() => setModal({ k: 'daily' })} dailyReady={dailyReady} onShop={() => setTab('shop')} />
          <TabBar tab={tab} onTab={goTab} badge={{ shop: chestReady, profile: false }} />
        </View>
      ) : route === 'online' ? (
        <OnlineRoot entry={onlineEntry} quick={onlineQuick} toast={toast} fx={hq} onExit={() => transition(() => { setRoute('tabs'); })} />
      ) : route === 'match' && launch ? (
        <Match key={matchKey} cfg={launch.cfg} teams={launch.teams} names={launch.names} onFinish={onFinish} onQuit={goHome} fx={hq} />
      ) : route === 'result' && result && launch ? (
        <View style={{ flex: 1 }}>
          <Space theme={out as any} stars={hq} />
          <Result r={result.r} reward={result.reward} names={launch.names} cup={result.cup} levelUp={result.levelUp}
            onAgain={() => (result.cup ? (result.cup.won && !result.cup.champion ? nextCup() : startMatch(buildLaunch('cup', p, { lvl: 0, rule: 'g3', tt: p.turnTime, opp: launch.teams[1], stage: 0 }))) : startMatch(buildLaunch(launch.mode, p, { lvl: launch.cfg.aiLvl, rule: launch.cfg.matchTime === 180 ? 't3' : launch.cfg.limit === 5 ? 'g5' : 'g3', tt: launch.cfg.turnTime, opp: launch.teams[1], stage: 0 })))}
            onHome={goHome} />
        </View>
      ) : null}

      {overlays.length ? (() => {
        const o = overlays[overlays.length - 1];
        return (
          <Animated.View key={o.k + ('id' in o ? o.id : '')} entering={FadeIn.duration(200)} style={[StyleSheet.absoluteFill, { zIndex: 55, backgroundColor: C.bg }]}>
            <Space theme="base" dim={.15} stars={hq} />
            {o.k === 'profile' ? <PublicProfile id={o.id} onBack={popOverlay} toast={toast} />
              : o.k === 'chat' ? <Chat id={o.id} onBack={popOverlay} toast={toast} />
                : o.k === 'club' ? <ClubPage id={o.id} onBack={popOverlay} toast={toast} />
                  : (<View style={{ flex: 1 }}><Header title="تیم من" en="SQUAD · DISCS · LOADOUT" onBack={popOverlay} /><TeamScreen top={ins.top + 76} bottom={ins.bottom + 8} toast={toast} /></View>)}
          </Animated.View>
        );
      })() : null}

      {sheet ? (
        <Sheet ref={sheetRef} key={sheet.k} onClosed={() => setSheet(null)} title={sheet.k === 'setup' ? sheet.mode.name : 'تنظیمات'} en={sheet.k === 'setup' ? sheet.mode.en : 'SYSTEMS'} accent={sheet.k === 'setup' ? sheet.mode.color : C.sky} height={sheet.k === 'setup' ? .9 : .78}>
          {sheet.k === 'setup' ? <Setup mode={sheet.mode} onStart={startMatch} onTeam={() => { sheetRef.current?.close(); pushOverlay({ k: 'team' }); }} />
            : <Settings toast={toast} replayIntro={() => { sheetRef.current?.close(); setIntro(true); }} />}
        </Sheet>
      ) : null}

      {modal?.k === 'daily' ? (
        <Modal onClose={() => setModal(null)}>
          <DailyCard ready={dailyReady} streak={p.streak} lastDaily={p.lastDaily} onClaim={claimDaily} onClose={() => setModal(null)} />
        </Modal>
      ) : modal?.k === 'chest' ? (
        <Modal onClose={() => setModal(null)} accent={modal.premium ? C.gold : C.cyan}>
          <ChestOpen prize={modal.prize} premium={modal.premium} onDone={() => setModal(null)} />
        </Modal>
      ) : null}

      <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: '#02030b', zIndex: 90 }, veilSt]} />

      {auth.recovery ? <RecoveryModal toast={toast} /> : null}
      {intro ? <Intro onDone={() => setIntro(false)} /> : null}
    </View>
    </OracleProvider>
    </NavCtx.Provider>
  );
}

function DailyCard({ ready, streak, lastDaily, onClaim, onClose }: { ready: boolean; streak: number; lastDaily: number; onClaim: () => void; onClose: () => void }) {
  const next = ready ? (Date.now() - lastDaily < 2 * DAY ? (streak % 7) + 1 : 1) : streak;
  const left = Math.max(0, lastDaily + DAY - Date.now()), h = Math.floor(left / 3600000), m = Math.ceil((left % 3600000) / 60000);
  return (
    <View style={{ padding: 18, alignItems: 'center' }}>
      <Img src={UI2.c_calendar} style={{ width: 96, height: 96 }} />
      <T s="جایزه‌ی روزانه" style={{ fontFamily: F.title, fontSize: 21, marginTop: 4 }} />
      <T s="هر روز سر بزن، جایزه‌ها بزرگ‌تر می‌شن" style={{ color: C.dim, fontSize: 12, marginTop: 2 }} />
      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', justifyContent: 'center', marginTop: 14 }}>
        {DAILY.map((d, i) => {
          const day = i + 1, got = ready ? day < next : day <= next, cur = ready && day === next;
          return (
            <View key={i} style={[st.day, day === 7 && { width: 132 }, got && { borderColor: C.green, backgroundColor: 'rgba(61,255,168,.1)' }, cur && { borderColor: C.gold, backgroundColor: 'rgba(255,210,87,.16)', shadowColor: C.gold, shadowOpacity: .8, shadowRadius: 10 }]}>
              <T s={`روز ${fa(day)}`} style={{ fontSize: 10, color: cur ? C.gold : C.dim }} />
              <Img src={day === 7 ? UI2.x_chest : d.gems ? UI2.x_gem : UI2.c_coin} style={{ width: 34, height: 34, marginVertical: 2 }} />
              <T s={d.gems ? `${fa(d.coins)}+${fa(d.gems)}💎` : fa(d.coins)} style={{ fontFamily: F.bold, fontSize: 10 }} />
              {got ? <View style={st.tick}><T s="✓" style={{ fontSize: 10, color: '#03140c', fontFamily: F.bold }} /></View> : null}
            </View>
          );
        })}
      </View>
      <View style={{ alignSelf: 'stretch', marginTop: 16 }}>
        {ready ? <Btn label={`دریافت جایزه‌ی روز ${fa(next)}`} onPress={onClaim} colors={G.gold} />
          : <Btn label={`جایزه‌ی بعدی: ${fa(h)}س ${fa(m)}د`} onPress={onClose} colors={G.dark} small />}
      </View>
    </View>
  );
}

export default function App() {
  const [loaded] = useFonts({ Orbitron_700Bold, Orbitron_900Black, Exo2_600SemiBold, Exo2_800ExtraBold, Vazirmatn_500Medium, Vazirmatn_800ExtraBold });
  if (!loaded) return <View style={{ flex: 1, backgroundColor: C.bg }} />;
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <StoreProvider><Shell /></StoreProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const st = StyleSheet.create({
  toast: { position: 'absolute', left: 0, right: 0, alignItems: 'center', zIndex: 99 },
  toastIn: { maxWidth: '90%', flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 22, backgroundColor: 'rgba(10,16,44,.96)', borderWidth: 1, shadowColor: '#000', shadowOpacity: .5, shadowRadius: 10, elevation: 10 },
  day: { width: 62, alignItems: 'center', paddingVertical: 8, margin: 3, borderRadius: 14, borderWidth: 1, borderColor: C.line, backgroundColor: 'rgba(8,12,34,.8)' },
  tick: { position: 'absolute', top: 4, left: 4, width: 16, height: 16, borderRadius: 8, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center' },
});
