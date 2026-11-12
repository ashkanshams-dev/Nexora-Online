// Navigator for the online area: hub → lobby → match → result, plus tournaments, ranks, arena, challenges.
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { BackHandler, View } from 'react-native';
import Animated, { FadeIn, FadeOut } from 'react-native-reanimated';
import Space from '../ui/Space';
import { Btn, T } from '../ui/kit';
import { Modal } from '../ui/Chrome';
import { C, F, G } from '../ui/theme';
import { playLoop, setAudioScene } from '../sound';
import { useAuth } from '../net/auth';
import { Mode, OnlineProfile, Room, errFa, rpc } from '../net/supabase';
import { useOracle } from '../oracle/Oracle';
import type { OnlineEntry } from '../nav';
import { LinkState, RoomLink } from './link';
import { ErrorState, S, Spinner, TS } from './ui';
import Hub from './Hub';
import Lobby from './Lobby';
import OnlineMatch, { OnlineOutcome } from './OnlineMatch';
import OnlineResult from './OnlineResult';
import Tournaments, { TournamentDetail } from './Tournaments';
import Ranks from './Ranks';
import Arena from './Arena';
import Challenges from './Challenges';

type R = { k: 'hub' } | { k: 'lobby' } | { k: 'match'; id: string } | { k: 'result'; o: OnlineOutcome; before: OnlineProfile | null }
  | { k: 'tours' } | { k: 'tour'; id: string } | { k: 'ranks'; tab?: 'top' | 'leagues' } | { k: 'arena' } | { k: 'challenges' };

type Props = { entry: OnlineEntry; quick?: Mode | null; onExit: () => void; toast: (m: string, k?: string) => void; fx: boolean };

export default function OnlineRoot({ entry, quick, onExit, toast, fx }: Props) {
  const auth = useAuth();
  const [stack, setStack] = useState<R[]>([entry === 'leagues' ? { k: 'ranks', tab: 'leagues' } : ({ k: entry } as R)]);
  const [link, setLink] = useState<RoomLink | null>(null);
  const [ls, setLs] = useState<LinkState | null>(null);
  const [connErr, setConnErr] = useState<string | null>(null);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const skip = useRef<string | null>(null);
  const firstLoad = useRef(true);
  const before = useRef<OnlineProfile | null>(null);
  const top = stack[stack.length - 1];
  // audio: lobby/result inside a room = ducked music, match = no music, other online pages = menu
  useEffect(() => { setAudioScene(top.k === 'match' ? 'match' : 'room'); }, [top.k]);   // v8: no menu music anywhere online
  useEffect(() => () => setAudioScene('menu'), []);

  // guests are signed in anonymously on first visit
  const connect = useCallback(() => { setConnErr(null); auth.ensure().then(id => { if (!id) setConnErr('اتصال به سرور برقرار نشد'); }, e => setConnErr(errFa(e))); }, [auth.ensure]);
  useEffect(() => { connect(); }, []);

  useEffect(() => {
    if (!link) { setLs(null); return; }
    setLs(link.state);
    return link.subscribe(() => setLs(link.state));
  }, [link]);
  useEffect(() => () => { if (link) { rpc('leave_room', { p_room: link.id }).catch(() => {}); link.destroy(); } }, [link]);

  const push = (r: R) => setStack(s => [...s, r]);
  const pop = () => setStack(s => (s.length > 1 ? s.slice(0, -1) : s));
  const replaceTop = (r: R) => setStack(s => [...s.slice(0, -1), r]);
  const dropRoom = () => setStack(s => { const k = s.filter(x => x.k !== 'lobby' && x.k !== 'match' && x.k !== 'result'); return k.length ? k : [{ k: 'hub' }]; });

  const enterRoom = useCallback((room: Room) => {
    if (!auth.uid) return;
    if (link && link.id === room.id) { setStack(s => [...s.filter(x => x.k !== 'lobby' && x.k !== 'match' && x.k !== 'result'), { k: 'lobby' }]); return; }
    link?.destroy();
    firstLoad.current = true; skip.current = null;
    const l = new RoomLink(room.id, auth.uid, auth.profile?.username || 'Pilot');
    setLink(l);
    setStack(s => [...s.filter(x => x.k !== 'lobby' && x.k !== 'match' && x.k !== 'result'), { k: 'lobby' }]);
  }, [auth.uid, auth.profile?.username, link]);

  const leaveRoom = useCallback(async () => {
    setConfirmLeave(false);
    const l = link; if (!l) { dropRoom(); return; }
    try { await rpc('leave_room', { p_room: l.id }); } catch { }
    l.destroy(); setLink(null); dropRoom(); playLoop('music');
  }, [link]);

  // Oracle "find me a quick match": once connected, run quick_match and drop straight into the lobby
  const oracle = useOracle();
  const quickDone = useRef(false);
  useEffect(() => {
    if (!quick || !auth.uid || quickDone.current) return;
    quickDone.current = true; oracle.react('search');
    rpc<Room>('quick_match', { p_mode: quick, p_kind: 'quick' }).then(r => enterRoom(r), e => toast(errFa(e), 'err'));
  }, [auth.uid, quick]);

  // room state → navigation
  useEffect(() => {
    if (!link || !ls || !ls.loaded) return;
    const room = ls.room;
    if (ls.gone) {
      if (top.k === 'lobby' || top.k === 'result') { toast(room ? 'از اتاق خارج شدی' : 'اتاق بسته شد', 'err'); link.destroy(); setLink(null); dropRoom(); }
      return;
    }
    if (!room) return;
    if (firstLoad.current) {
      firstLoad.current = false;
      // a host coming back to a room stuck in "playing" (e.g. app was killed) ends that match
      if (room.status === 'playing' && room.current_match && room.host === link.me) {
        skip.current = room.current_match; rpc('abandon_match', { p_match: room.current_match }).then(() => link.ping(), () => {}); return;
      }
    }
    if (top.k === 'lobby' && room.status === 'playing' && room.current_match && room.current_match !== skip.current) {
      before.current = auth.profile; push({ k: 'match', id: room.current_match });
    }
  }, [ls, top.k]);

  // Android back
  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (top.k === 'match') return true; // the match has its own quit dialog
      back(); return true;
    });
    return () => sub.remove();
  });
  const back = () => {
    if (top.k === 'lobby') { setConfirmLeave(true); return; }
    if (top.k === 'result') { replaceTop({ k: 'lobby' }); return; }
    if (stack.length > 1) pop(); else { if (link) leaveRoom(); onExit(); }
  };

  if (!auth.uid) {
    return (
      <View style={{ flex: 1 }}>
        <Space theme="base" stars={fx} />
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: S.xl }}>
          {connErr ? <ErrorState msg={connErr} onRetry={connect} /> : <><Spinner size={40} /><T s="در حال اتصال به سرور…" style={{ marginTop: S.m, color: C.dim, fontSize: TS.body }} /></>}
          <Btn label="بازگشت" small colors={G.dark} onPress={onExit} style={{ marginTop: S.l, width: 160 }} />
        </View>
      </View>
    );
  }

  const key = top.k + (top.k === 'tour' || top.k === 'match' ? (top as any).id : '');
  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      {top.k !== 'match' ? <Space theme={top.k === 'result' ? (top.o.myTeam !== null && top.o.winner === top.o.myTeam ? 'win' : top.o.winner === -1 || top.o.myTeam === null ? 'system' : 'lose') : 'base'} dim={.1} stars={fx} /> : null}
      <Animated.View key={key} entering={FadeIn.duration(220)} exiting={FadeOut.duration(120)} style={{ flex: 1 }}>
        {top.k === 'hub' ? <Hub onBack={back} onRoom={enterRoom} toast={toast} onNav={n => push({ k: n })} />
          : top.k === 'lobby' && link ? <Lobby link={link} toast={toast} onLeave={() => setConfirmLeave(true)} onWatch={() => { const m = ls?.room?.current_match; if (m) { before.current = auth.profile; skip.current = null; push({ k: 'match', id: m }); } }} />
            : top.k === 'match' && link ? (
              <OnlineMatch key={top.id} link={link} matchId={top.id} toast={toast} fx={fx}
                onFinish={o => { skip.current = top.id; playLoop('music'); replaceTop({ k: 'result', o, before: before.current }); }}
                onExit={() => { skip.current = top.id; playLoop('music'); replaceTop({ k: 'lobby' }); link.refresh(); }} />
            ) : top.k === 'result' ? <OnlineResult o={top.o} before={top.before} onLobby={() => replaceTop({ k: 'lobby' })} onLeave={leaveRoom} />
              : top.k === 'tours' ? <Tournaments onBack={back} toast={toast} onOpen={id => push({ k: 'tour', id })} />
                : top.k === 'tour' ? <TournamentDetail id={top.id} onBack={back} toast={toast} onRoom={enterRoom} />
                  : top.k === 'ranks' ? <Ranks onBack={back} toast={toast} tab={top.tab} />
                    : top.k === 'arena' ? <Arena onBack={back} toast={toast} onRoom={enterRoom} />
                      : top.k === 'challenges' ? <Challenges onBack={back} toast={toast} />
                        : <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Spinner /></View>}
      </Animated.View>
      {confirmLeave ? (
        <Modal onClose={() => setConfirmLeave(false)} accent={C.red}>
          <View style={{ padding: S.l }}>
            <T s="خروج از اتاق؟" style={{ fontFamily: F.title, fontSize: 20, textAlign: 'center' }} />
            <T s="جایگاهت آزاد می‌شود و از لابی خارج می‌شوی." style={{ fontSize: TS.small, color: C.dim, textAlign: 'center', marginTop: S.s, marginBottom: S.l }} />
            <Btn label="ماندن" onPress={() => setConfirmLeave(false)} />
            <View style={{ height: S.s }} />
            <Btn label="خروج" small colors={G.red} onPress={leaveRoom} />
          </View>
        </Modal>
      ) : null}
    </View>
  );
}
