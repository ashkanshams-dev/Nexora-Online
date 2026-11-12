// Auth + online profile provider.
// - Guests are signed in anonymously on demand (first visit to any online screen).
// - Email sign-up / sign-in / password reset with Supabase Auth; e-mail links deep-link back
//   into the app (nexora://auth in a dev build, exp://…/--/auth in Expo Go) and are handled here.
// - Guest → email upgrade keeps the same user id (and all progress) via auth.updateUser.
// - The user's own profiles row is kept live with a Realtime postgres_changes subscription.
import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import * as Linking from 'expo-linking';
import { ONLINE_CONFIGURED, OnlineProfile, errFa, supabase } from './supabase';

type Res = { ok: true; info?: string } | { ok: false; error: string };
type Ctx = {
  ready: boolean; configured: boolean; session: Session | null; uid: string | null; email: string | null; isGuest: boolean;
  profile: OnlineProfile | null; recovery: boolean;
  ensure: () => Promise<string | null>;
  signUp: (email: string, password: string) => Promise<Res>;
  signIn: (email: string, password: string) => Promise<Res>;
  upgrade: (email: string, password: string) => Promise<Res>;
  resetPassword: (email: string) => Promise<Res>;
  setNewPassword: (password: string) => Promise<Res>;
  resend: (email: string) => Promise<Res>;
  signOut: () => Promise<void>;
  setUsername: (name: string) => Promise<Res>;
  refreshProfile: () => Promise<OnlineProfile | null>;
  endRecovery: () => void;
};
const AuthCtx = createContext<Ctx>(null as any);
export const useAuth = () => useContext(AuthCtx);
export const useProfile = () => useContext(AuthCtx).profile;

export const authRedirect = () => Linking.createURL('auth');

function parseAuthUrl(url: string) {
  const i = url.indexOf('#'), q = url.indexOf('?');
  const raw = i >= 0 ? url.slice(i + 1) : q >= 0 ? url.slice(q + 1) : '';
  const out: Record<string, string> = {};
  for (const kv of raw.split('&')) { const [k, v] = kv.split('='); if (k) out[decodeURIComponent(k)] = decodeURIComponent((v || '').replace(/\+/g, ' ')); }
  return out;
}

export function AuthProvider({ children, toast }: { children: React.ReactNode; toast?: (m: string, k?: string) => void }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [profile, setProfile] = useState<OnlineProfile | null>(null);
  const [recovery, setRecovery] = useState(false);
  const uid = session?.user?.id ?? null;
  const ensuring = useRef<Promise<string | null> | null>(null);
  const toastRef = useRef(toast); toastRef.current = toast;

  useEffect(() => {
    if (!ONLINE_CONFIGURED) { setReady(true); return; }
    let alive = true;
    supabase.auth.getSession().then(({ data }) => { if (alive) { setSession(data.session); setReady(true); } }).catch(() => alive && setReady(true));
    const { data: sub } = supabase.auth.onAuthStateChange((ev, s) => {
      setSession(s);
      if (ev === 'PASSWORD_RECOVERY') setRecovery(true);
      if (ev === 'SIGNED_OUT') setProfile(null);
    });
    return () => { alive = false; sub.subscription.unsubscribe(); };
  }, []);

  // e-mail links (confirm sign-up, confirm e-mail change, password recovery)
  useEffect(() => {
    if (!ONLINE_CONFIGURED) return;
    const handle = async (url: string | null) => {
      if (!url || !/auth/.test(url) || !/(access_token|error_description|code)=/.test(url)) return;
      const q = parseAuthUrl(url);
      if (q.error_description || q.error) { toastRef.current?.(q.error_code === 'otp_expired' ? 'لینک ایمیل منقضی شده؛ دوباره درخواست بده' : errFa(q.error_description || q.error), 'err'); return; }
      if (q.access_token && q.refresh_token) {
        const { error } = await supabase.auth.setSession({ access_token: q.access_token, refresh_token: q.refresh_token });
        if (error) { toastRef.current?.(errFa(error), 'err'); return; }
        if (q.type === 'recovery') setRecovery(true);
        else toastRef.current?.(q.type === 'email_change' ? 'ایمیل تأیید شد' : 'حسابت تأیید شد · خوش اومدی!', 'ok');
      }
    };
    Linking.getInitialURL().then(handle).catch(() => {});
    const sub = Linking.addEventListener('url', e => { handle(e.url); });
    return () => sub.remove();
  }, []);

  const refreshProfile = useCallback(async () => {
    const { data: u } = await supabase.auth.getSession();
    const id = u.session?.user?.id; if (!id) return null;
    const { data, error } = await supabase.from('profiles').select('*').eq('id', id).maybeSingle();
    if (error) return null;
    setProfile(data as OnlineProfile | null); return data as OnlineProfile | null;
  }, []);

  // live own profile row
  useEffect(() => {
    if (!uid) { setProfile(null); return; }
    let alive = true;
    supabase.from('profiles').select('*').eq('id', uid).maybeSingle().then(({ data }) => { if (alive && data) setProfile(data as OnlineProfile); }, () => {});
    supabase.from('profiles').update({ online_at: new Date().toISOString() }).eq('id', uid).then(() => {}, () => {});
    const ch = supabase.channel(`profile:${uid}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'profiles', filter: `id=eq.${uid}` }, pl => { if (alive) setProfile(prev => ({ ...(prev || {}), ...(pl.new as any) })); })
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [uid]);

  const ensure = useCallback(async () => {
    if (!ONLINE_CONFIGURED) return null;
    const { data } = await supabase.auth.getSession();
    if (data.session) return data.session.user.id;
    if (!ensuring.current) ensuring.current = (async () => {
      try {
        const { data: d, error } = await supabase.auth.signInAnonymously();
        if (error) throw error; return d.user?.id ?? null;
      } finally { ensuring.current = null; }
    })();
    return ensuring.current;
  }, []);

  const wrap = (fn: () => Promise<Res>) => fn().catch((e): Res => ({ ok: false, error: errFa(e) }));
  const signUp = useCallback((email: string, password: string) => wrap(async () => {
    const { data, error } = await supabase.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: authRedirect() } });
    if (error) throw error;
    // e-mail confirmation is ON: no session until the link is opened
    if (!data.session) return { ok: true, info: 'confirm' };
    return { ok: true };
  }), []);
  const signIn = useCallback((email: string, password: string) => wrap(async () => {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw error; return { ok: true };
  }), []);
  const upgrade = useCallback((email: string, password: string) => wrap(async () => {
    const { error } = await supabase.auth.updateUser({ email: email.trim(), password }, { emailRedirectTo: authRedirect() });
    if (error) throw error;
    return { ok: true, info: 'confirm' };
  }), []);
  const resetPassword = useCallback((email: string) => wrap(async () => {
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: authRedirect() });
    if (error) throw error; return { ok: true };
  }), []);
  const setNewPassword = useCallback((password: string) => wrap(async () => {
    const { error } = await supabase.auth.updateUser({ password });
    if (error) throw error; setRecovery(false); return { ok: true };
  }), []);
  const resend = useCallback((email: string) => wrap(async () => {
    const { error } = await supabase.auth.resend({ type: 'signup', email: email.trim(), options: { emailRedirectTo: authRedirect() } });
    if (error) throw error; return { ok: true };
  }), []);
  const signOut = useCallback(async () => {
    try { await supabase.rpc('leave_all_rooms'); } catch { }
    await supabase.auth.signOut().catch(() => {});
    setProfile(null);
  }, []);
  const setUsername = useCallback((name: string) => wrap(async () => {
    const n = name.trim();
    if (n.length < 3 || n.length > 20) return { ok: false, error: 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد' };
    if (!/^[A-Za-z0-9_.\- \u0600-\u06FF\u200c]+$/.test(n)) return { ok: false, error: 'فقط حروف، عدد، فاصله و _ . - مجاز است' };
    const { data: s } = await supabase.auth.getSession(); const id = s.session?.user?.id;
    if (!id) return { ok: false, error: 'اول وارد حساب شو' };
    const { error } = await supabase.from('profiles').update({ username: n }).eq('id', id);
    if (error) throw error;
    setProfile(prev => (prev ? { ...prev, username: n } : prev)); return { ok: true };
  }), []);

  const v = useMemo<Ctx>(() => ({
    ready, configured: ONLINE_CONFIGURED, session, uid, email: session?.user?.email || null,
    isGuest: !!session?.user && (session.user.is_anonymous ?? !session.user.email), profile, recovery,
    ensure, signUp, signIn, upgrade, resetPassword, setNewPassword, resend, signOut, setUsername, refreshProfile, endRecovery: () => setRecovery(false),
  }), [ready, session, uid, profile, recovery, ensure, signUp, signIn, upgrade, resetPassword, setNewPassword, resend, signOut, setUsername, refreshProfile]);
  return <AuthCtx.Provider value={v}>{children}</AuthCtx.Provider>;
}
