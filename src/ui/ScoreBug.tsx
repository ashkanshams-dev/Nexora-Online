// Broadcast-style match scoreboard: team wings (crest + 3-letter code + player name), central score slab
// with match clock, and a shrinking turn-timer underline on the side that is to play.
import React, { memo } from 'react';
import { StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Img, T } from './kit';
import { C, F } from './theme';
import { TEAM_IMG } from '../game/assets';
import { Team } from '../game/data';
import { teamKey } from '../game/util';

export type BugSide = { team: Team; name: string; score: number; color: string; on: boolean };
const code = (t: Team) => (t.name.replace(/[^A-Za-z ]/g, '').split(' ').filter(Boolean).length > 1
  ? t.name.split(' ').filter(w => /[A-Za-z]/.test(w) && w !== 'II').map(w => w[0]).join('').slice(0, 3)
  : t.name.replace(/[^A-Za-z]/g, '').slice(0, 3)).toUpperCase() || 'NXG';

const Wing = memo(function Wing({ s, right, tl, timed }: { s: BugSide; right?: boolean; tl: number; timed: boolean }) {
  return (
    <View style={[st.wing, right ? st.wingR : st.wingL]}>
      <LinearGradient colors={right ? ['rgba(6,9,26,.94)', s.color + (s.on ? '88' : '33'), s.color + (s.on ? 'cc' : '44')] : [s.color + (s.on ? 'cc' : '44'), s.color + (s.on ? '88' : '33'), 'rgba(6,9,26,.94)']}
        start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }} style={StyleSheet.absoluteFill} />
      <View style={[st.wingIn, right && { flexDirection: 'row-reverse' }]}>
        <View style={[st.crest, { borderColor: s.on ? '#fff' : 'rgba(255,255,255,.25)', shadowColor: s.color, shadowOpacity: s.on ? 1 : 0 }]}>
          <Img src={TEAM_IMG[teamKey(s.team)]} style={{ width: 34, height: 34, borderRadius: 17 }} />
        </View>
        <View style={{ flex: 1, alignItems: right ? 'flex-end' : 'flex-start', marginHorizontal: 6 }}>
          <T s={code(s.team)} style={st.code} />
          <T s={s.name} n={1} style={[st.pname, { color: s.on ? '#fff' : 'rgba(225,235,255,.6)' }]} />
        </View>
      </View>
      {s.on ? (
        <View style={st.timerTrack}>
          <View style={{ height: '100%', width: `${(timed ? tl : 1) * 100}%`, alignSelf: right ? 'flex-end' : 'flex-start', backgroundColor: timed && tl < .25 ? C.red : '#fff', borderRadius: 2 }} />
        </View>
      ) : null}
    </View>
  );
});

function ScoreBug({ left, right, clock, sudden, tl, timed, status }: { left: BugSide; right: BugSide; clock: string; sudden: boolean; tl: number; timed: boolean; status?: string }) {
  return (
    <View style={{ alignItems: 'center' }} pointerEvents="none">
      <View style={st.bug}>
        <Wing s={left} tl={tl} timed={timed} />
        <View style={st.slab}>
          <LinearGradient colors={['#1a2350', '#0a0f2a', '#05081a']} style={StyleSheet.absoluteFill} />
          <View style={st.slabGloss} />
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <T s={String(left.score)} style={[st.score, left.on && { textShadowColor: left.color, textShadowRadius: 10 }]} />
            <View style={st.sep} />
            <T s={String(right.score)} style={[st.score, right.on && { textShadowColor: right.color, textShadowRadius: 10 }]} />
          </View>
        </View>
        <Wing s={right} right tl={tl} timed={timed} />
      </View>
      <View style={[st.clock, sudden && { backgroundColor: C.gold, borderColor: C.gold }]}>
        <T s={sudden ? 'GOLDEN GOAL' : clock || '00:00'} style={[st.clockT, sudden && { color: '#1b1200' }]} />
      </View>
      {status ? <View style={st.status}><T s={status} n={1} style={{ fontFamily: F.bold, fontSize: 11, color: '#fff' }} /></View> : null}
    </View>
  );
}
export default memo(ScoreBug);

const st = StyleSheet.create({
  bug: { flexDirection: 'row', height: 52, borderRadius: 14, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,.14)', backgroundColor: 'rgba(5,8,22,.92)', shadowColor: '#000', shadowOpacity: .6, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 10 },
  wing: { flex: 1, minWidth: 0, justifyContent: 'center' },
  wingL: {}, wingR: {},
  wingIn: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 6 },
  crest: { width: 40, height: 40, borderRadius: 20, borderWidth: 1.5, alignItems: 'center', justifyContent: 'center', backgroundColor: '#04060f', shadowRadius: 8, shadowOffset: { width: 0, height: 0 } },
  code: { fontFamily: F.title, fontSize: 15, letterSpacing: 1.5, color: '#fff' },
  pname: { fontFamily: F.body, fontSize: 10, marginTop: 1 },
  timerTrack: { position: 'absolute', left: 6, right: 6, bottom: 3, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,.18)', overflow: 'hidden' },
  slab: { width: 92, alignItems: 'center', justifyContent: 'center', borderLeftWidth: 1, borderRightWidth: 1, borderColor: 'rgba(255,255,255,.12)' },
  slabGloss: { position: 'absolute', left: 0, right: 0, top: 0, height: '45%', backgroundColor: 'rgba(255,255,255,.06)' },
  score: { fontFamily: F.title, fontSize: 26, color: '#fff', minWidth: 22, textAlign: 'center' },
  sep: { width: 8, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,.55)', marginHorizontal: 7 },
  clock: { marginTop: -1, paddingHorizontal: 12, height: 20, borderBottomLeftRadius: 8, borderBottomRightRadius: 8, backgroundColor: 'rgba(5,8,22,.92)', borderWidth: 1, borderTopWidth: 0, borderColor: 'rgba(255,255,255,.14)', justifyContent: 'center' },
  clockT: { fontFamily: F.head, fontSize: 11, letterSpacing: 2, color: '#e6eeff' },
  status: { marginTop: 6, paddingHorizontal: 12, height: 24, borderRadius: 12, justifyContent: 'center', backgroundColor: 'rgba(5,8,22,.75)', borderWidth: 1, borderColor: 'rgba(255,255,255,.14)' },
});
