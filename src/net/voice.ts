// Voice chat over LiveKit — loaded lazily and fully guarded.
// Expo Go does not ship the WebRTC native module, so nothing from @livekit/* or livekit-client is
// imported at module scope anywhere: it is required inside try/catch only when the user joins voice.
import Constants, { ExecutionEnvironment } from 'expo-constants';
import { PermissionsAndroid, Platform } from 'react-native';
import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from './supabase';
import { setVoiceActive } from '../sound';

export type VoiceSupport = { ok: true } | { ok: false; reason: string };
let support: VoiceSupport | null = null;
let lk: any = null, lkc: any = null;

export function voiceSupport(): VoiceSupport {
  if (support) return support;
  if (Platform.OS === 'web') return (support = { ok: false, reason: 'چت صوتی فقط روی موبایل' });
  if (Constants.executionEnvironment === ExecutionEnvironment.StoreClient) return (support = { ok: false, reason: 'چت صوتی فقط در نسخه‌ی Development Build' });
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    lk = require('@livekit/react-native');
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    lkc = require('livekit-client');
    lk.registerGlobals();
    support = { ok: true };
  } catch {
    support = { ok: false, reason: 'چت صوتی فقط در نسخه‌ی Development Build' };
  }
  return support;
}

export type VoiceState = { status: 'off' | 'connecting' | 'on' | 'error'; mic: boolean; speaker: boolean; canPublish: boolean; speaking: string[]; error?: string };
type Listener = (s: VoiceState) => void;

// One voice session per room. Emits state for UI; never throws to callers.
export class Voice {
  private vid = Math.random().toString(36).slice(2);
  state: VoiceState = { status: 'off', mic: false, speaker: true, canPublish: false, speaking: [] };
  private room: any = null; private ls = new Set<Listener>(); private alive = true;
  constructor(private roomId: string) {}
  on(l: Listener) { this.ls.add(l); l(this.state); return () => { this.ls.delete(l); }; }
  private set(p: Partial<VoiceState>) { this.state = { ...this.state, ...p }; setVoiceActive(this.vid, this.state.status === 'on' || this.state.mic); this.ls.forEach(l => l(this.state)); }

  async join() {
    const sup = voiceSupport();
    if (!sup.ok) { this.set({ status: 'error', error: sup.reason }); return; }
    if (this.state.status === 'connecting' || this.state.status === 'on') return;
    this.set({ status: 'connecting', error: undefined });
    try {
      const { data, error } = await supabase.functions.invoke('livekit-token', { body: { room_id: this.roomId } });
      if (error) {
        let status = 0, body: any = null;
        if (error instanceof FunctionsHttpError) { status = error.context?.status ?? 0; try { body = await error.context.json(); } catch { } }
        if (status === 503 || body?.error === 'voice_not_configured') throw new Error('چت صوتی هنوز فعال نشده');
        if (status === 403) throw new Error('برای چت صوتی باید داخل اتاق باشی');
        throw new Error('اتصال به سرور صدا ناموفق بود');
      }
      if (!this.alive) return;
      if (data.canPublish && Platform.OS === 'android') {
        const g = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO);
        if (g !== PermissionsAndroid.RESULTS.GRANTED) data.canPublish = false;
      }
      await lk.AudioSession.startAudioSession();
      const room = new lkc.Room({ adaptiveStream: false, dynacast: false });
      this.room = room;
      room.on(lkc.RoomEvent.ActiveSpeakersChanged, (sp: any[]) => this.set({ speaking: sp.map(p => p.identity) }));
      room.on(lkc.RoomEvent.Disconnected, () => { if (this.alive) this.set({ status: 'off', mic: false, speaking: [] }); });
      room.on(lkc.RoomEvent.TrackSubscribed, (_t: any, _pub: any, part: any) => { try { part.setVolume?.(this.state.speaker ? 1 : 0); } catch { } });
      await room.connect(data.url, data.token, { autoSubscribe: true });
      if (!this.alive) { room.disconnect(); return; }
      this.set({ status: 'on', canPublish: !!data.canPublish, mic: false });
      if (data.canPublish) await this.setMic(true);
    } catch (e: any) {
      this.set({ status: 'error', error: e?.message && /[\u0600-\u06FF]/.test(e.message) ? e.message : 'اتصال صدا ناموفق بود' });
      this.leave(true);
    }
  }
  async setMic(on: boolean) {
    if (!this.room || !this.state.canPublish) return;
    try { await this.room.localParticipant.setMicrophoneEnabled(on); this.set({ mic: on }); } catch { this.set({ mic: false }); }
  }
  setSpeaker(on: boolean) {
    this.set({ speaker: on });
    try { this.room?.remoteParticipants?.forEach((p: any) => p.setVolume?.(on ? 1 : 0)); } catch { }
  }
  leave(keepError = false) {
    const r = this.room; this.room = null;
    try { r?.disconnect(); } catch { }
    try { if (r) lk?.AudioSession?.stopAudioSession(); } catch { }
    if (!keepError) this.set({ status: 'off', mic: false, speaking: [] });
  }
  destroy() { this.alive = false; this.leave(); this.ls.clear(); setVoiceActive(this.vid, false); }
}
