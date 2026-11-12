// FastLink (v8): low-latency game transport over LiveKit WebRTC data channels.
// Supabase Realtime is a websocket relay (client → Phoenix server → client) and adds jitter under load.
// LiveKit Cloud routes every player to its nearest edge SFU and forwards data packets over SCTP/UDP,
// so a shot reaches the other phone noticeably faster and steadier. It is joined in a SEPARATE LiveKit room
// ("nexora-<room>-g", data only, no audio) so it never touches voice chat. Fully optional: if WebRTC is
// unavailable or blocked, RoomLink keeps sending over Supabase and nothing changes for the player.
import { supabase } from './supabase';
import { voiceSupport } from './voice';

let lkc: any = null;
const enc = (s: string) => {
  if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s);
  const u = unescape(encodeURIComponent(s)), a = new Uint8Array(u.length); for (let i = 0; i < u.length; i++) a[i] = u.charCodeAt(i); return a;
};
const dec = (b: Uint8Array) => {
  if (typeof TextDecoder !== 'undefined') return new TextDecoder().decode(b);
  let s = ''; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); try { return decodeURIComponent(escape(s)); } catch { return s; }
};

export class FastLink {
  private room: any = null; private alive = true; ready = false;
  private retry: ReturnType<typeof setTimeout> | null = null; private tries = 0;
  constructor(private roomId: string, private onMsg: (m: any) => void) { this.start(); }

  private async start() {
    if (!this.alive) return;
    try {
      if (!voiceSupport().ok) return;   // web / Expo Go: no WebRTC → Supabase only
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      lkc = lkc || require('livekit-client');
      const { data, error } = await supabase.functions.invoke('livekit-token', { body: { room_id: this.roomId, purpose: 'game' } });
      if (error || !data?.token || !this.alive) throw new Error('token');
      const room = new lkc.Room({ adaptiveStream: false, dynacast: false, disconnectOnPageLeave: false });
      room.on(lkc.RoomEvent.DataReceived, (payload: Uint8Array, _p: any, _k: any, topic?: string) => {
        if (topic && topic !== 'g') return;
        try { this.onMsg(JSON.parse(dec(payload))); } catch { }
      });
      room.on(lkc.RoomEvent.Disconnected, () => { this.ready = false; if (this.alive) this.again(); });
      await room.connect(data.url, data.token, { autoSubscribe: false });
      if (!this.alive) { room.disconnect(); return; }
      this.room = room; this.ready = true; this.tries = 0;
    } catch { this.ready = false; this.again(); }
  }
  private again() {
    if (!this.alive || this.tries > 4) return;
    this.tries++; if (this.retry) clearTimeout(this.retry);
    this.retry = setTimeout(() => this.start(), 1500 * this.tries);
  }
  /** returns true when the packet was handed to WebRTC */
  send(m: any, reliable = true) {
    if (!this.ready || !this.room) return false;
    try { this.room.localParticipant.publishData(enc(JSON.stringify(m)), { reliable, topic: 'g' }); return true; } catch { return false; }
  }
  destroy() { this.alive = false; this.ready = false; if (this.retry) clearTimeout(this.retry); try { this.room?.disconnect(); } catch { } this.room = null; }
}
