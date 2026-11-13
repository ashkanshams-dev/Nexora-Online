import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Image, StyleSheet, View, useWindowDimensions } from 'react-native';
import { Canvas, Picture, SkPicture, useImage, createPicture } from '@shopify/react-native-skia';
import { useSharedValue, SharedValue } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Engine, MatchCfg } from '../game/engine';
import { computeView, frame, staticLayer, toWorld, View as GView } from '../game/render';
import { FIELDS, Team } from '../game/data';
import ScoreBug from '../ui/ScoreBug';
import { ARROW_IMG, BALL_IMG, FIELD_IMG, GOAL_IMG, TEAM_IMG } from '../game/assets';
import { teamKey } from '../game/util';
import { C, F } from '../ui/theme';
import { Btn, Panel, Press, T } from '../ui/kit';
import { G } from '../ui/theme';
import { sfx, buzz, playLoop, stopLoop } from '../sound';
import { useOracle } from '../oracle/Oracle';
import { coachMiss } from '../oracle/coach';

export type MatchResult = { score: [number, number]; teams: [Team, Team]; ai: boolean; aiLvl: number };

export default function Match({ cfg, teams, names, onFinish, onQuit, fx = true }: { cfg: MatchCfg; teams: [Team, Team]; names: [string, string]; onFinish: (r: MatchResult) => void; onQuit: () => void; fx?: boolean }) {
  const { width: W, height: H } = useWindowDimensions();
  const ins = useSafeAreaInsets();
  const eng = useMemo(() => new Engine(cfg), []);
  const f = FIELDS[cfg.field];
  const im = {
    field: useImage(FIELD_IMG[f.id]), goal: useImage(GOAL_IMG[f.gs]), ball: useImage(BALL_IMG['b' + cfg.ball]),
    t0: useImage(TEAM_IMG[teamKey(teams[0])]), t1: useImage(TEAM_IMG[teamKey(teams[1])]),
    arrow: { headE: useImage(ARROW_IMG.head_e), headS: useImage(ARROW_IMG.head_s), shaftE: useImage(ARROW_IMG.shaft_e), shaftS: useImage(ARROW_IMG.shaft_s) },
  };
  const view = useMemo<GView>(() => computeView(eng, W, H, ins.top + 86, ins.bottom + 22), [W, H, ins.top, ins.bottom]);
  const bg = useMemo(() => (im.field ? staticLayer(eng, view, im) : null), [im.field, view]);
  const picSet = useRef<(p: SkPicture) => void>(() => {});
  const [hud, setHud] = useState({ s0: 0, s1: 0, turn: 0 as 0 | 1, clock: '', tl: 1, sudden: false });
  const [paused, setPaused] = useState(false);
  const pausedRef = useRef(false); pausedRef.current = paused;
  const banner = useRef(new Animated.Value(0)).current; const [bText, setBText] = useState({ t: '', s: '', c: C.gold });
  const ended = useRef(false);
  const imRef = useRef(im); imRef.current = im; const bgRef = useRef(bg); bgRef.current = bg; const viewRef = useRef(view); viewRef.current = view;

  const oracle = useOracle(); const oracleRef = useRef(oracle); oracleRef.current = oracle;
  useEffect(() => oracle.setScene('match'), []);
  const human = (t: 0 | 1) => !(cfg.ai && t === 1);
  const co = useRef({ shotTeam: -1 as number, touched: false, lastTip: 0, misses: 0, reminded: -1 as number, turnN: 0 });

  const showBanner = (t: string, s: string, c: string) => {
    setBText({ t, s, c }); banner.setValue(0);
    Animated.sequence([Animated.spring(banner, { toValue: 1, useNativeDriver: true, speed: 14, bounciness: 12 }), Animated.delay(1100), Animated.timing(banner, { toValue: 2, duration: 300, useNativeDriver: true })]).start();
  };

  useEffect(() => {
    sfx('whistle'); playLoop('crowd'); stopLoop('music');
    let raf = 0, last = 0, alive = true; const t0 = Date.now();
    const loop = (ts: number) => {
      if (!alive) return;
      const dt = last ? (ts - last) / 1000 : 1 / 60; last = ts;
      if (!pausedRef.current) eng.update(dt);
      // events → sound / haptics / hud
      if (eng.events.length) {
        for (const ev of eng.events) {
          if (ev.t === 'hit') { if (ev.ball) co.current.touched = true; sfx(ev.ball ? 'hitb' : 'hitp', ev.power); if (ev.power > .35) buzz(ev.power > .7 ? 'medium' : 'light'); }
          else if (ev.t === 'wall') sfx('wall', ev.power);
          else if (ev.t === 'post') { sfx('post', ev.power); buzz('medium'); }
          else if (ev.t === 'shot') { buzz('light'); co.current.shotTeam = ev.team; co.current.touched = false; }
          else if (ev.t === 'turn') {
            const c = co.current; c.turnN++;
            if (c.shotTeam >= 0 && human(c.shotTeam as 0 | 1) && !c.touched) {
              c.misses++;
              const tipText = coachMiss(eng.lastPower, c.misses);
              if (tipText && Date.now() - c.lastTip > 18000) { c.lastTip = Date.now(); oracleRef.current.coach(tipText, eng.lastPower > .9 ? 'focus' : 'idea'); }
            }
            c.shotTeam = -1;
          }
          else if (ev.t === 'goal') {
            if (ev.nogoal) showBanner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
            else { co.current.touched = true; sfx('goal'); sfx('roar'); buzz('heavy'); showBanner('گل!', names[ev.team], ev.team === 0 ? C.cyan : C.red); if (human(ev.team)) oracleRef.current.react('goal'); }
          } else if (ev.t === 'clock') showBanner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
          else if (ev.t === 'end' && !ended.current) {
            ended.current = true; sfx('final'); stopLoop('crowd');
            setTimeout(() => onFinish({ score: ev.score, teams, ai: cfg.ai, aiLvl: cfg.aiLvl }), 900);
          }
        }
        eng.events.length = 0;
      }
      // turn-timer reminder for the human whose turn it is
      if (cfg.turnTime > 0 && eng.phase === 'aim' && eng.tleft < 5 && eng.tleft > 0 && human(eng.turn) && co.current.reminded !== co.current.turnN && !pausedRef.current) {
        co.current.reminded = co.current.turnN; oracleRef.current.coach('۵ ثانیه وقت داری! ⏱ یک ضربه بزن.', 'alert');
      }
      if (!fx && eng.parts.length > 40) eng.parts.length = 40;
      const v = viewRef.current;
      picSet.current(frame(eng, v, imRef.current, bgRef.current, cfg.ball, (Date.now() - t0) / 1000));
      const m = Math.max(0, Math.ceil(eng.mleft));
      const clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`) : `تا ${cfg.limit} گل`;
      const tl = cfg.turnTime > 0 && eng.phase === 'aim' ? Math.max(0, eng.tleft / cfg.turnTime) : 1;
      setHud(h => (h.s0 !== eng.score[0] || h.s1 !== eng.score[1] || h.turn !== eng.turn || h.clock !== clock || Math.abs(h.tl - tl) > .02 || h.sudden !== eng.sudden) ? { s0: eng.score[0], s1: eng.score[1], turn: eng.turn, clock, tl, sudden: eng.sudden } : h);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => { alive = false; cancelAnimationFrame(raf); stopLoop('crowd'); };
  }, []);

  const touch = {
    onStartShouldSetResponder: () => true,
    onMoveShouldSetResponder: () => true,
    onResponderGrant: (e: any) => { const p = toWorld(viewRef.current, e.nativeEvent.locationX, e.nativeEvent.locationY); if (eng.pick(p.x, p.y)) buzz('light'); },
    onResponderMove: (e: any) => { const p = toWorld(viewRef.current, e.nativeEvent.locationX, e.nativeEvent.locationY); eng.move(p.x, p.y); },
    onResponderRelease: () => eng.release(),
    onResponderTerminate: () => eng.cancel(),
  };

  const bScale = banner.interpolate({ inputRange: [0, 1, 2], outputRange: [.3, 1, 1.25] });
  const bOp = banner.interpolate({ inputRange: [0, .2, 1, 2], outputRange: [0, 1, 1, 0] });

  return (
    <View style={{ flex: 1, backgroundColor: '#02040c' }}>
      <View style={StyleSheet.absoluteFill} {...touch}>
        <Stage w={W} h={H} bind={f => (picSet.current = f)} />
      </View>
      {/* HUD: broadcast score bug */}
      <View style={[s.hud, { top: ins.top + 6 }]} pointerEvents="box-none">
        <Press onPress={() => setPaused(true)} style={s.pause}><T s="II" style={{ fontFamily: F.title, fontSize: 13, color: '#fff' }} /></Press>
        <View style={{ flex: 1 }} pointerEvents="none">
          <ScoreBug left={{ team: teams[0], name: names[0], score: hud.s0, color: C.cyan, on: hud.turn === 0 }} right={{ team: teams[1], name: names[1], score: hud.s1, color: C.red, on: hud.turn === 1 }}
            clock={hud.clock} sudden={hud.sudden} tl={hud.tl} timed={cfg.turnTime > 0} status={hud.turn === 0 ? 'نوبت توئه' : 'نوبت حریف'} />
        </View>
      </View>
      {/* goal banner */}
      <Animated.View pointerEvents="none" style={[s.banner, { opacity: bOp, transform: [{ scale: bScale }] }]}>
        <T s={bText.t} style={{ fontFamily: F.title, fontSize: 54, letterSpacing: 4, color: '#fff', textShadowColor: bText.c, textShadowRadius: 24 }} />
        {bText.s ? <T s={bText.s} style={{ fontFamily: F.head, fontSize: 13, letterSpacing: 3, color: bText.c, marginTop: 4 }} /> : null}
      </Animated.View>
      {paused ? (
        <View style={s.overlay}>
          <Panel style={{ padding: 22, width: '82%', alignItems: 'stretch' }} glow>
            <T s="توقف" style={{ fontFamily: F.title, fontSize: 24, letterSpacing: 6, textAlign: 'center', marginBottom: 18 }} />
            <Btn label="ادامه" onPress={() => setPaused(false)} />
            <View style={{ height: 12 }} />
            <Btn label="شروع دوباره" colors={G.dark} small onPress={() => { eng.score = [0, 0]; eng.mleft = cfg.matchTime; eng.sudden = false; eng.reset(0); setPaused(false); }} />
            <View style={{ height: 12 }} />
            <Btn label="خروج" colors={G.red} onPress={() => { stopLoop('crowd'); onQuit(); }} />
          </Panel>
        </View>
      ) : null}
    </View>
  );
}

// The match canvas never re-renders through React: each frame's SkPicture is pushed into a
// Reanimated shared value and Skia draws it straight on the UI thread.
const Stage = React.memo(function Stage({ w, h, bind }: { w: number; h: number; bind: (f: (p: SkPicture) => void) => void }) {
  const pic = useSharedValue<SkPicture>(EMPTY());
  useEffect(() => { bind((p: SkPicture) => { pic.value = p; }); }, []);
  return <Canvas style={{ width: w, height: h }} pointerEvents="none"><Picture picture={pic as SharedValue<SkPicture>} /></Canvas>;
});
let _empty: SkPicture | null = null;
const EMPTY = () => _empty || (_empty = createPicture(() => {}));

function Side({ team, name, on, color, right }: { team: Team; name: string; on: boolean; color: string; right?: boolean }) {
  return (
    <View style={{ flex: 1, flexDirection: right ? 'row-reverse' : 'row', alignItems: 'center' }}>
      <View style={[s.logo, { borderColor: on ? color : 'rgba(255,255,255,.15)', shadowColor: color, shadowOpacity: on ? .9 : 0, shadowRadius: 10 }]}>
        <Image source={TEAM_IMG[teamKey(team)]} style={{ width: 34, height: 34, borderRadius: 17 }} />
      </View>
      <View style={{ flex: 1, alignItems: right ? 'flex-end' : 'flex-start', marginHorizontal: 6 }}>
        <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: 12, color: on ? '#fff' : C.dim }} />
        <T s={on ? 'نوبت توئه' : ' '} style={{ fontFamily: F.head, fontSize: 8, letterSpacing: 1.5, color }} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  hud: { position: 'absolute', left: 10, right: 10, flexDirection: 'row', alignItems: 'center' },
  pause: { width: 38, height: 38, borderRadius: 12, backgroundColor: 'rgba(5,8,22,.9)', borderWidth: 1, borderColor: 'rgba(255,255,255,.16)', alignSelf: 'flex-start', marginTop: 7, alignItems: 'center', justifyContent: 'center', marginRight: 8 },
  board: { flex: 1, height: 60, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8 },
  score: { fontFamily: F.title, fontSize: 26, color: '#fff' },
  logo: { width: 40, height: 40, borderRadius: 20, borderWidth: 2, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' },
  turnBar: { position: 'absolute', left: 60, right: 12, height: 4, borderRadius: 3, backgroundColor: 'rgba(255,255,255,.08)', overflow: 'hidden' },
  banner: { position: 'absolute', left: 0, right: 0, top: '38%', alignItems: 'center' },
  overlay: { position: "absolute", left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(2,4,14,.7)', alignItems: 'center', justifyContent: 'center' },
});
