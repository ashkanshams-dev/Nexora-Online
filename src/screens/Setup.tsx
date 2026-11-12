import React, { useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { BALL_IMG, FIELD_THUMB, TEAM_IMG, UI, UI2 } from '../game/assets';
import { BALL_NAMES, FIELDS, FORMS, TEAMS, Team } from '../game/data';
import { teamById, teamKey } from '../game/util';
import { Profile, useStore } from '../store';
import { Btn, Float, Img, Press, Pulse, Segment, T } from '../ui/kit';
import { C, F, G } from '../ui/theme';
import type { MatchCfg } from '../game/engine';
import { discStats } from '../net/discs';

export type ModeKey = 'quick' | 'local' | 'cup' | 'galaxy' | 'train';
export type Mode = { k: ModeKey; img: any; name: string; en: string; desc: string; reward: string; color: string };
export const MODES: Mode[] = [
  { k: 'quick', img: UI.portal_gamepad, name: 'بازی سریع', en: 'QUICK MATCH', desc: 'یک مسابقه‌ی فوری مقابل هوش مصنوعی', reward: 'سکه، XP و جام', color: C.cyan },
  { k: 'cup', img: UI.portal_globe, name: 'جام نکسورا', en: 'NEXORA CUP', desc: 'سه حریف پشت سر هم تا فینال؛ هر مرحله سخت‌تر', reward: '۲ برابر جایزه + ۲۰ الماس قهرمانی', color: C.gold },
  { k: 'galaxy', img: UI.portal_galaxy, name: 'چالش کهکشانی', en: 'GALAXY CHALLENGE', desc: 'دو دقیقه مقابل ربات افسانه‌ای', reward: '۳ برابر جایزه', color: C.violet },
  { k: 'local', img: UI.portal_friends, name: 'دو نفره', en: 'LOCAL 2 PLAYER', desc: 'با دوستت روی یک گوشی بازی کن', reward: 'فقط برای افتخار', color: C.green },
  { k: 'train', img: UI.portal_brain, name: 'تمرین', en: 'TRAINING', desc: 'بدون تایمر، ربات آسان، برای گرم کردن دست', reward: 'XP کم، بدون جام', color: C.sky },
];

export type Launch = { cfg: MatchCfg; teams: [Team, Team]; names: [string, string]; mode: ModeKey; stage?: number };
const pool = () => TEAMS.filter(t => t.cat === 'club' || t.cat === 'nat' || t.cat === 'elite');
export const pickOpp = () => { const p = pool(); return p[Math.floor(Math.random() * p.length)]; };
const boosted = (t: Team) => t.cat === 'vip' || t.cat === 'leg';

export function buildLaunch(mode: ModeKey, p: Profile, opt: { lvl: 0 | 1 | 2; rule: 'g3' | 'g5' | 't3'; tt: number; opp: Team; stage?: number }): Launch {
  const me = teamById(p.team), oppForm = Math.floor(Math.random() * FORMS.length);
  const ai = mode !== 'local'; let lvl = opt.lvl, limit = opt.rule === 'g5' ? 5 : 3, matchTime = opt.rule === 't3' ? 180 : 0, tt = opt.tt;
  if (mode === 'cup') { lvl = (Math.min(2, opt.stage || 0)) as 0 | 1 | 2; limit = 3; matchTime = 0; }
  if (mode === 'galaxy') { lvl = 2; matchTime = 120; limit = 99; }
  if (mode === 'train') { lvl = 0; tt = 0; }
  const cfg: MatchCfg = { field: p.field, ball: p.ball, forms: [p.form, ai ? oppForm : p.form], ai, aiLvl: lvl, limit, matchTime, turnTime: tt, vip: [boosted(me), boosted(opt.opp)], first: 0, stats: [discStats(me.id), discStats(opt.opp.id)] };
  return { cfg, teams: [me, opt.opp], names: [p.name, ai ? opt.opp.name : 'بازیکن ۲'], mode, stage: opt.stage };
}

export default function Setup({ mode, onStart, onTeam }: { mode: Mode; onStart: (l: Launch) => void; onTeam: () => void }) {
  const { p, set } = useStore();
  const [lvl, setLvl] = useState<0 | 1 | 2>(p.aiLvl);
  const [rule, setRule] = useState<'g3' | 'g5' | 't3'>(p.limit === 5 ? 'g5' : 'g3');
  const [tt, setTt] = useState(p.turnTime);
  const [opp, setOpp] = useState<Team>(pickOpp);
  const me = teamById(p.team);
  const showLvl = mode.k === 'quick', showRule = mode.k === 'quick' || mode.k === 'local', showTT = mode.k !== 'train';
  const go = () => { set({ aiLvl: lvl, limit: rule === 'g5' ? 5 : 3, turnTime: tt }); onStart(buildLaunch(mode.k, p, { lvl, rule, tt, opp, stage: 0 })); };
  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 30 }} showsVerticalScrollIndicator={false}>
      <View style={{ alignItems: 'center', height: 150, justifyContent: 'center' }}>
        <Pulse size={120} color={mode.color + '55'} />
        <Float amp={5}><Img src={mode.img} style={{ width: 140, height: 150 }} /></Float>
      </View>
      <T s={mode.desc} style={{ textAlign: 'center', color: '#c8e2ff', fontSize: 14 }} />
      <View style={[s.reward, { borderColor: mode.color + '66', backgroundColor: mode.color + '18' }]}><Img src={UI2.c_coin} style={{ width: 22, height: 22, marginLeft: 6 }} /><T s={mode.reward} style={{ fontSize: 12, color: '#ffe9a8' }} /></View>

      {/* versus */}
      <View style={s.vs}>
        <LinearGradient colors={['rgba(79,227,255,.18)', 'rgba(8,12,34,0)', 'rgba(255,74,90,.18)']} start={{ x: 0, y: .5 }} end={{ x: 1, y: .5 }} style={[StyleSheet.absoluteFill, { borderRadius: 20 }]} />
        <Press onPress={onTeam} style={{ flex: 1, alignItems: 'center' }}>
          <View style={[s.disc, { borderColor: C.cyan, shadowColor: C.cyan }]}><Img src={TEAM_IMG[teamKey(me)]} style={s.logo} /></View>
          <T s={me.name} n={1} style={s.tn} /><T s="تغییر تیم" style={[s.small, { color: C.cyan }]} />
        </Press>
        <Img src={UI.vs} style={{ width: 70, height: 60 }} />
        <Press onPress={() => mode.k !== 'local' && setOpp(pickOpp())} style={{ flex: 1, alignItems: 'center' }}>
          <View style={[s.disc, { borderColor: C.red, shadowColor: C.red }]}><Img src={mode.k === 'local' ? TEAM_IMG[teamKey(me)] : TEAM_IMG[teamKey(opp)]} style={s.logo} /></View>
          <T s={mode.k === 'local' ? 'بازیکن ۲' : opp.name} n={1} style={s.tn} /><T s={mode.k === 'local' ? ' ' : 'حریف دیگر ↻'} style={[s.small, { color: C.red }]} />
        </Press>
      </View>

      {mode.k === 'cup' ? (
        <View style={s.cupRow}>
          {['یک‌چهارم', 'نیمه‌نهایی', 'فینال'].map((n, i) => (
            <View key={n} style={{ flex: 1, alignItems: 'center' }}>
              <Img src={i === 2 ? UI2.x_trophy : UI2.x_medal} style={{ width: 46, height: 46, opacity: i === 0 ? 1 : .55 }} />
              <T s={n} style={{ fontSize: 11, color: i === 0 ? C.gold : C.dim }} />
              <T s={['آسان', 'معمولی', 'سخت'][i]} style={{ fontSize: 10, color: C.dim2 }} />
            </View>
          ))}
        </View>
      ) : null}

      {showLvl ? <Row label="سختی"><Segment value={lvl} onChange={setLvl} items={[[0, 'آسان'], [1, 'معمولی'], [2, 'سخت']]} /></Row> : null}
      {showRule ? <Row label="قانون"><Segment value={rule} onChange={setRule} items={[['g3', 'تا ۳ گل'], ['g5', 'تا ۵ گل'], ['t3', '۳ دقیقه']]} accent={C.violet} /></Row> : null}
      {showTT ? <Row label="زمان نوبت"><Segment value={tt} onChange={setTt} items={[[0, 'خاموش'], [10, '۱۰ث'], [15, '۱۵ث'], [20, '۲۰ث']]} accent={C.green} /></Row> : null}

      <Press onPress={onTeam} style={s.load}>
        <Img src={BALL_IMG['b' + p.ball]} style={{ width: 38, height: 38, borderRadius: 19 }} />
        <View style={{ flex: 1, marginHorizontal: 10, alignItems: 'flex-end' }}>
          <T s={`${BALL_NAMES[p.ball]} · ${FIELDS[p.field].name}`} n={1} style={{ fontFamily: F.bold, fontSize: 12 }} />
          <T s={`ترکیب ${FORMS[p.form][0]} · تجهیزات`} style={{ fontSize: 11, color: C.dim }} />
        </View>
        <Img src={FIELD_THUMB[FIELDS[p.field].id]} style={{ width: 30, height: 40, borderRadius: 6 }} fit="cover" />
      </Press>

      <Btn label={mode.k === 'cup' ? 'شروع جام' : 'شروع بازی'} onPress={go} style={{ marginTop: 18 }} colors={mode.k === 'cup' ? G.gold : G.primary} />
    </ScrollView>
  );
}

const Row = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <View style={{ marginTop: 14 }}>
    <T s={label} style={{ fontFamily: F.bold, fontSize: 13, textAlign: 'right', marginBottom: 6, color: C.dim }} />
    {children}
  </View>
);

const s = StyleSheet.create({
  reward: { flexDirection: 'row-reverse', alignSelf: 'center', alignItems: 'center', marginTop: 10, paddingHorizontal: 12, height: 32, borderRadius: 16, borderWidth: 1 },
  vs: { flexDirection: 'row', alignItems: 'center', marginTop: 16, paddingVertical: 14, paddingHorizontal: 8, borderRadius: 20, backgroundColor: 'rgba(10,18,48,.85)', borderWidth: 1, borderColor: C.line },
  disc: { width: 72, height: 72, borderRadius: 36, borderWidth: 3, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816', shadowOpacity: .8, shadowRadius: 12, shadowOffset: { width: 0, height: 0 }, elevation: 8 },
  logo: { width: 64, height: 64, borderRadius: 32 },
  tn: { fontFamily: F.bold, fontSize: 12, marginTop: 6 },
  small: { fontSize: 10, marginTop: 1 },
  cupRow: { flexDirection: 'row-reverse', marginTop: 12, paddingVertical: 10, borderRadius: 18, backgroundColor: 'rgba(255,210,87,.07)', borderWidth: 1, borderColor: 'rgba(255,210,87,.25)' },
  load: { flexDirection: 'row', alignItems: 'center', marginTop: 16, padding: 10, borderRadius: 16, backgroundColor: 'rgba(10,18,48,.85)', borderWidth: 1, borderColor: C.line },
});
