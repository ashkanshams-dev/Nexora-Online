import React, { memo, useState } from 'react';
import { ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Canvas, Circle, Path, Skia, SweepGradient, vec } from '@shopify/react-native-skia';
import { TEAM_IMG, UI, UI2 } from '../game/assets';
import { ACHS } from '../game/meta';
import { teamById, teamKey } from '../game/util';
import { LEAGUE_FA, league, level, useStore } from '../store';
import { Bar, Btn, Enter, Float, Img, Panel, Pulse, T, Title } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, sfx } from '../sound';
import OnlineProfileCard from './OnlineProfileCard';

const MEDAL = ['medal_bronze', 'medal_silver', 'medal_gold', 'medal_epic', 'shield_epic', 'shield_crown'];

function Profile({ top, bottom, toast }: { top: number; bottom: number; toast: (m: string, k?: string) => void }) {
  const { p, set } = useStore(); const lv = level(p.xp), lg = league(p.trophies), t = teamById(p.team);
  const [name, setName] = useState(p.name);
  const wr = p.played ? Math.round(p.wins / p.played * 100) : 0;
  const commit = () => set({ name: name.trim().slice(0, 16) || 'Pilot' });
  const stats: [any, string, string | number][] = [
    [UI2.x_ball, 'بازی', p.played], [UI2.x_medal, 'برد', p.wins], [UI2.x_shield, 'باخت', p.losses],
    [UI2.x_star, 'مساوی', p.draws], [UI2.x_statue, 'گل زده', p.goalsFor], [UI2.x_trophy, 'جام قهرمانی', p.cupsWon],
  ];
  const claim = (id: string) => {
    const a = ACHS.find(x => x.id === id)!; if (p.claimedAch.includes(id)) return;
    set(q => ({ claimedAch: [...q.claimedAch, id], coins: q.coins + a.coins, gems: q.gems + a.gems })); sfx('goal'); buzz('success');
    toast(`+${fa(a.coins)} سکه · +${fa(a.gems)} الماس`, 'ok');
  };
  return (
    <ScrollView contentContainerStyle={{ paddingTop: top, paddingBottom: bottom + 10 }} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
      <Enter i={0}><OnlineProfileCard toast={toast} /></Enter>
      <Title s="پروفایل آفلاین" en="OFFLINE CAREER" accent="#ff7bd5" />
      <Enter i={0} style={{ paddingHorizontal: 16 }}>
        <Panel style={{ padding: 16, alignItems: 'center' }} accent="#ff7bd5" glow>
          <LinearGradient colors={['rgba(255,123,213,.18)', 'transparent']} style={StyleSheet.absoluteFill} />
          <Img src={UI2.d_banner} style={{ position: 'absolute', right: 8, top: 8, width: 34, height: 92, opacity: .8 }} />
          <Img src={UI2.d_banner} style={{ position: 'absolute', left: 8, top: 8, width: 34, height: 92, opacity: .8 }} />
          <View style={{ width: 120, height: 120, alignItems: 'center', justifyContent: 'center' }}>
            <Pulse size={110} color="rgba(255,123,213,.35)" />
            <View style={s.av}><Img src={TEAM_IMG[teamKey(t)]} style={{ width: 92, height: 92, borderRadius: 46 }} /></View>
            <View style={s.lv}><T s={`سطح ${fa(lv.level)}`} style={{ fontFamily: F.bold, fontSize: 11, color: '#1b0e00' }} /></View>
          </View>
          <TextInput value={name} onChangeText={setName} onEndEditing={commit} onBlur={commit} maxLength={16} selectionColor={C.cyan}
            style={s.name} />
          <T s="برای تغییر نام لمس کن" style={{ fontSize: 10, color: C.dim2, marginTop: 2 }} />
          <View style={{ alignSelf: 'stretch', marginTop: 10 }}><Bar v={lv.cur / lv.need} color="#ff7bd5" color2={C.violet} h={10} /></View>
          <T s={`${lv.cur} / ${lv.need} XP`} style={{ fontFamily: F.head, fontSize: 10, color: C.dim, marginTop: 4 }} />
        </Panel>
      </Enter>

      <Enter i={1} style={{ paddingHorizontal: 16, marginTop: 10 }}>
        <Panel style={{ flexDirection: 'row-reverse', alignItems: 'center', padding: 12 }} accent={C.gold}>
          <Float amp={3}><Img src={(UI as any)[MEDAL[Math.min(lg.idx, 5)]]} style={{ width: 66, height: 66 }} /></Float>
          <View style={{ flex: 1, marginHorizontal: 10 }}>
            <T s={`لیگ ${LEAGUE_FA[lg.name]}`} style={{ fontFamily: F.title, fontSize: 17, textAlign: 'right' }} />
            <View style={{ marginTop: 6 }}><Bar v={(p.trophies - lg.from) / (lg.to - lg.from)} color={C.gold} color2={C.orange} /></View>
            <T s={`${fa(p.trophies)} از ${fa(lg.to)} جام`} style={{ fontSize: 11, color: C.dim, marginTop: 4, textAlign: 'right' }} />
          </View>
        </Panel>
      </Enter>

      <Enter i={2} style={{ paddingHorizontal: 16, marginTop: 10 }}>
        <Panel style={{ flexDirection: 'row-reverse', alignItems: 'center', padding: 14 }}>
          <Ring v={wr} />
          <View style={{ flex: 1, marginRight: 14 }}>
            <Row k="بهترین رکورد برد پیاپی" v={fa(p.bestStreak)} />
            <Row k="برد پیاپی فعلی" v={fa(p.winStreak)} />
            <Row k="تفاضل گل" v={`${p.goalsFor - p.goalsAgainst >= 0 ? '+' : ''}${fa(p.goalsFor - p.goalsAgainst)}`} />
            <Row k="دیسک‌های باز شده" v={fa(p.ownedTeams.length)} />
          </View>
        </Panel>
      </Enter>

      <View style={{ flexDirection: 'row-reverse', flexWrap: 'wrap', paddingHorizontal: 12, marginTop: 6 }}>
        {stats.map(([img, k, v], i) => (
          <Enter key={k} i={i + 3} style={{ width: '33.33%', padding: 4 }}>
            <Panel style={{ alignItems: 'center', paddingVertical: 10 }} accent="transparent">
              <Img src={img} style={{ width: 40, height: 40 }} />
              <T s={typeof v === 'number' ? fa(v) : v} style={{ fontFamily: F.title, fontSize: 18, marginTop: 2 }} />
              <T s={k} style={{ fontSize: 10, color: C.dim }} />
            </Panel>
          </Enter>
        ))}
      </View>

      <Title s="دستاوردها" en="ACHIEVEMENTS" accent={C.green} />
      {ACHS.map((a, i) => {
        const cur = Math.min(a.max, a.cur(p)), done = cur >= a.max, claimed = p.claimedAch.includes(a.id);
        return (
          <Enter key={a.id} i={i} style={{ paddingHorizontal: 16, marginBottom: 8 }}>
            <Panel style={{ flexDirection: 'row-reverse', alignItems: 'center', padding: 10, opacity: claimed ? .6 : 1 }} accent={done && !claimed ? C.green : 'transparent'} glow={done && !claimed}>
              <Img src={UI2[a.icon]} style={{ width: 50, height: 50 }} />
              <View style={{ flex: 1, marginHorizontal: 10 }}>
                <View style={{ flexDirection: 'row-reverse', justifyContent: 'space-between' }}>
                  <T s={a.name} style={{ fontFamily: F.bold, fontSize: 13 }} />
                  <T s={`${fa(cur)}/${fa(a.max)}`} style={{ fontSize: 11, color: done ? C.green : C.dim }} />
                </View>
                <T s={a.desc} style={{ fontSize: 11, color: C.dim, textAlign: 'right' }} />
                <View style={{ marginTop: 5 }}><Bar v={cur / a.max} h={6} color={done ? C.green : C.cyan} /></View>
              </View>
              <View style={{ width: 74 }}>
                {claimed ? <T s="✓ دریافت شد" style={{ fontSize: 10, color: C.green, textAlign: 'center' }} />
                  : done ? <Btn small label="دریافت" colors={G.green} onPress={() => claim(a.id)} style={{ marginTop: 0 }} />
                    : <View style={{ alignItems: 'center' }}><Img src={UI2.c_coin} style={{ width: 24, height: 24 }} /><T s={`+${a.coins}`} style={{ fontFamily: F.head, fontSize: 10, color: C.gold }} /></View>}
              </View>
            </Panel>
          </Enter>
        );
      })}
    </ScrollView>
  );
}
export default memo(Profile);

const Row = ({ k, v }: { k: string; v: string }) => (
  <View style={{ flexDirection: 'row-reverse', justifyContent: 'space-between', paddingVertical: 4, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,.08)' }}>
    <T s={k} style={{ fontSize: 12, color: C.dim }} /><T s={v} style={{ fontFamily: F.bold, fontSize: 13 }} />
  </View>
);

// win-rate ring (Skia arc)
function Ring({ v }: { v: number }) {
  const S = 92, sw = 8, r = (S - sw) / 2;
  const path = React.useMemo(() => { const pb = Skia.PathBuilder.Make(); pb.arcToOval(Skia.XYWHRect(sw / 2, sw / 2, r * 2, r * 2), -90, Math.max(.5, v / 100 * 359.9), true); return pb.build(); }, [v]);
  return (
    <View style={{ width: S, height: S, alignItems: 'center', justifyContent: 'center' }}>
      <Canvas style={{ position: 'absolute', width: S, height: S }}>
        <Circle cx={S / 2} cy={S / 2} r={r} style="stroke" strokeWidth={sw} color="rgba(255,255,255,0.08)" />
        <Path path={path} style="stroke" strokeWidth={sw} strokeCap="round">
          <SweepGradient c={vec(S / 2, S / 2)} colors={[C.cyan, C.green, C.cyan]} />
        </Path>
      </Canvas>
      <T s={`${fa(v)}٪`} style={{ fontFamily: F.title, fontSize: 18 }} />
      <T s="درصد برد" style={{ fontSize: 9, color: C.dim }} />
    </View>
  );
}

const s = StyleSheet.create({
  av: { width: 104, height: 104, borderRadius: 52, borderWidth: 3, borderColor: '#ff7bd5', alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' },
  lv: { position: 'absolute', bottom: 2, paddingHorizontal: 10, height: 22, borderRadius: 11, backgroundColor: C.gold, justifyContent: 'center' },
  name: { color: C.text, fontFamily: F.title, fontSize: 20, textAlign: 'center', marginTop: 6, minWidth: 180, borderBottomWidth: 1, borderBottomColor: 'rgba(255,123,213,.4)', paddingVertical: 4 },
});
