// RoomLink: one realtime connection per joined room, shared by the lobby and the online match.
//  - postgres_changes on rooms / room_players  → refetch room state (debounced)
//  - broadcast 'chat'                           → text chat
//  - broadcast 'g'                              → match netcode (see match/net.ts)
//  - broadcast 'sync'                           → "please refetch" pings (covers DELETEs, kicks)
//  - presence (key = user id)                   → who is connected right now
import { useSyncExternalStore } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { Room, RoomPlayer, supabase } from '../net/supabase';
import { Voice } from '../net/voice';
import { sfx } from '../sound';

export type Chat = { id: string; uid: string; name: string; text: string; ts: number };
export type LinkState = {
  room: Room | null; players: RoomPlayer[]; online: Record<string, { name: string }>; chat: Chat[];
  connected: boolean; loaded: boolean; gone: boolean; unread: number;
  /** smoothed round-trip time (ms) to the room host (or a peer when I am the host); null = unknown */
  rtt: number | null;
};

export class RoomLink {
  readonly id: string; readonly me: string; myName: string;
  state: LinkState = { room: null, players: [], online: {}, chat: [], connected: false, loaded: false, gone: false, unread: 0, rtt: null };
  private ch: RealtimeChannel | null = null;
  private ls = new Set<() => void>();
  private gl = new Set<(m: any, from?: string) => void>();
  private t: ReturnType<typeof setTimeout> | null = null;
  private poll: ReturnType<typeof setInterval> | null = null;
  private beat: ReturnType<typeof setInterval> | null = null;
  private pinger: ReturnType<typeof setInterval> | null = null;
  private dead = false; private seenOnline = new Set<string>();
  voice: Voice;
  chatOpen = false;

  constructor(id: string, me: string, myName: string) {
    this.id = id; this.me = me; this.myName = myName; this.voice = new Voice(id);
    this.connect();
    this.refresh();
    this.poll = setInterval(() => this.refresh(), 12000);
    // server sweeps players without a heartbeat for 45 s
    this.beat = setInterval(() => { supabase.rpc('heartbeat', { p_room: this.id }).then(() => {}, () => {}); }, 15000);
    supabase.rpc('heartbeat', { p_room: this.id }).then(() => {}, () => {});
    // RTT probe: tiny ping/pong broadcast every 3 s (never touches the DB)
    this.pinger = setInterval(() => this.probe(), 3000);
  }

  private probe() {
    if (!this.ch || !this.state.connected) return;
    const host = this.state.room?.host;
    const to = host && host !== this.me && this.state.online[host] ? host : Object.keys(this.state.online).find(k => k !== this.me);
    if (!to) { if (this.state.rtt !== null) this.set({ rtt: null }); return; }
    this.ch.send({ type: 'broadcast', event: 'pi', payload: { t: Date.now(), f: this.me, to } }).catch(() => {});
  }

  private set(p: Partial<LinkState>) { this.state = { ...this.state, ...p }; this.ls.forEach(l => l()); }
  subscribe = (l: () => void) => { this.ls.add(l); return () => { this.ls.delete(l); }; };
  get = () => this.state;

  private connect() {
    const ch = supabase.channel(`room:${this.id}`, { config: { broadcast: { self: false, ack: false }, presence: { key: this.me } } });
    ch.on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${this.id}` }, () => this.soon())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'room_players', filter: `room_id=eq.${this.id}` }, () => this.soon())
      .on('broadcast', { event: 'sync' }, () => this.soon())
      .on('broadcast', { event: 'chat' }, ({ payload }) => this.addChat(payload as Chat))
      .on('broadcast', { event: 'pi' }, ({ payload }) => { const m = payload as any; if (m?.to === this.me) ch.send({ type: 'broadcast', event: 'po', payload: { t: m.t, to: m.f } }).catch(() => {}); })
      .on('broadcast', { event: 'po' }, ({ payload }) => {
        const m = payload as any; if (m?.to !== this.me || typeof m.t !== 'number') return;
        const r = Math.max(1, Date.now() - m.t); if (r > 10000) return;
        const prev = this.state.rtt; this.set({ rtt: Math.round(prev === null ? r : prev * .6 + r * .4) });
      })
      .on('broadcast', { event: 'g' }, ({ payload }) => { const m = payload as any; this.gl.forEach(f => f(m, m?.from)); })
      .on('presence', { event: 'sync' }, () => {
        const ps = ch.presenceState<{ name: string }>(); const online: LinkState['online'] = {};
        for (const k in ps) online[k] = { name: ps[k][0]?.name || '' };
        for (const k in online) if (!this.seenOnline.has(k)) { this.seenOnline.add(k); if (k !== this.me && this.state.connected) sfx('join'); }
        for (const k of Array.from(this.seenOnline)) if (!online[k]) { this.seenOnline.delete(k); if (k !== this.me) sfx('leave'); }
        this.set({ online }); this.soon();
      })
      .subscribe(async st => {
        if (this.dead) return;
        if (st === 'SUBSCRIBED') { this.set({ connected: true }); try { await ch.track({ name: this.myName }); } catch { } this.refresh(); }
        else if (st === 'CHANNEL_ERROR' || st === 'TIMED_OUT' || st === 'CLOSED') this.set({ connected: false });
      });
    this.ch = ch;
  }

  private soon() { if (this.t) clearTimeout(this.t); this.t = setTimeout(() => this.refresh(), 150); }

  async refresh() {
    if (this.dead) return;
    const [r, p] = await Promise.all([
      supabase.from('rooms').select('*').eq('id', this.id).maybeSingle(),
      supabase.from('room_players').select('*, profiles(username, avatar, avatar_url, level, rating, league, equipped_disc)').eq('room_id', this.id).order('joined_at'),
    ]).catch(() => [{ data: undefined, error: true }, { data: undefined, error: true }] as any[]);
    if (this.dead || r.error || p.error) return;
    const players = (p.data || []) as RoomPlayer[];
    const gone = !r.data || !players.some(x => x.user_id === this.me);
    this.set({ room: (r.data as Room) || this.state.room, players, loaded: true, gone });
  }

  ping() { this.ch?.send({ type: 'broadcast', event: 'sync', payload: {} }).catch(() => {}); }

  private addChat(c: Chat) {
    if (!c || typeof c.text !== 'string') return;
    const chat = this.state.chat.concat({ ...c, text: c.text.slice(0, 200) }).slice(-80);
    if (c.uid !== this.me) sfx('chat');
    this.set({ chat, unread: this.chatOpen || c.uid === this.me ? 0 : this.state.unread + 1 });
  }
  sendChat(text: string) {
    const t = text.trim().slice(0, 200); if (!t) return;
    const c: Chat = { id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, uid: this.me, name: this.myName, text: t, ts: Date.now() };
    this.addChat(c);
    this.ch?.send({ type: 'broadcast', event: 'chat', payload: c }).catch(() => {});
  }
  markRead() { if (this.state.unread) this.set({ unread: 0 }); }

  onGame(f: (m: any, from?: string) => void) { this.gl.add(f); return () => { this.gl.delete(f); }; }
  sendGame(m: any) { this.ch?.send({ type: 'broadcast', event: 'g', payload: { ...m, from: this.me } }).catch(() => {}); }

  destroy() {
    this.dead = true;
    if (this.t) clearTimeout(this.t); if (this.poll) clearInterval(this.poll); if (this.beat) clearInterval(this.beat); if (this.pinger) clearInterval(this.pinger);
    this.voice.destroy();
    if (this.ch) { const c = this.ch; this.ch = null; c.untrack().catch(() => {}).finally(() => supabase.removeChannel(c)); }
    this.ls.clear(); this.gl.clear();
  }
}

export function useLink(link: RoomLink) { return useSyncExternalStore(link.subscribe, link.get, link.get); }
