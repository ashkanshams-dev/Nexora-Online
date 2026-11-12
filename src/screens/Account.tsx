// Account section (Settings): guest / e-mail status, sign up, sign in, guest→email upgrade,
// forgot password, sign out, change username. Plus the password-recovery modal opened by e-mail links.
import React, { useState } from 'react';
import { View } from 'react-native';
import { UI2 } from '../game/assets';
import { Btn, Img, Panel, Press, Segment, T } from '../ui/kit';
import { Modal } from '../ui/Chrome';
import { C, F, G, fa } from '../ui/theme';
import { buzz } from '../sound';
import { useAuth } from '../net/auth';
import { Avatar, Field, S, TS } from '../online/ui';

const emailOk = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e.trim());

export default function Account({ toast }: { toast: (m: string, k?: string) => void }) {
  const a = useAuth();
  const [mode, setMode] = useState<'up' | 'in' | 'forgot'>('up');
  const [email, setEmail] = useState(''); const [pass, setPass] = useState(''); const [pass2, setPass2] = useState('');
  const [name, setName] = useState(''); const [editName, setEditName] = useState(false);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [sureOut, setSureOut] = useState(false);

  if (!a.configured) return null;
  const done = (r: { ok: boolean; error?: string; info?: string }, okMsg?: string) => {
    if (!r.ok) { setErr(r.error || 'خطا'); buzz('heavy'); return false; }
    setErr(null); if (okMsg) toast(okMsg, 'ok'); buzz('success'); return true;
  };
  const submit = async () => {
    setErr(null);
    if (!emailOk(email)) { setErr('ایمیل معتبر نیست'); return; }
    if (mode !== 'forgot' && pass.length < 6) { setErr('رمز عبور حداقل ۶ کاراکتر'); return; }
    if (mode === 'up' && pass !== pass2) { setErr('تکرار رمز عبور یکسان نیست'); return; }
    setBusy(true);
    try {
      if (mode === 'forgot') { if (done(await a.resetPassword(email))) setSent('reset'); }
      else if (mode === 'in') { if (done(await a.signIn(email, pass), 'وارد شدی')) { setPass(''); } }
      else if (a.uid && a.isGuest) { if (done(await a.upgrade(email, pass))) setSent('upgrade'); }
      else { const r = await a.signUp(email, pass); if (done(r)) setSent(r.ok && r.info === 'confirm' ? 'confirm' : null); }
    } finally { setBusy(false); }
  };
  const saveName = async () => { setBusy(true); const r = await a.setUsername(name); setBusy(false); if (done(r, 'نام کاربری تغییر کرد')) setEditName(false); };

  const signedEmail = a.uid && !a.isGuest;
  return (
    <Panel style={{ padding: S.m, marginBottom: S.s + 2 }} accent={C.cyan}>
      <View style={{ flexDirection: 'row-reverse', alignItems: 'center' }}>
        {a.profile ? <Avatar avatar={a.profile.equipped_disc || a.profile.avatar} url={a.profile.avatar_url} size={48} /> : <Img src={UI2.c_profile} style={{ width: 44, height: 44 }} />}
        <View style={{ flex: 1, marginRight: S.m, alignItems: 'flex-end' }}>
          <T s="حساب آنلاین" style={{ fontFamily: F.bold, fontSize: 15 }} />
          <T s={!a.uid ? 'وارد نشده‌ای' : a.isGuest ? `مهمان · ${a.profile?.username || ''}` : `${a.email} · ${a.profile?.username || ''}`} n={1} style={{ color: C.dim, fontSize: TS.cap, marginTop: 1 }} />
        </View>
        {a.profile ? <T s={`سطح ${fa(a.profile.level)}`} style={{ fontFamily: F.bold, fontSize: TS.cap, color: C.gold }} /> : null}
      </View>

      {a.profile ? (
        editName ? (
          <View style={{ marginTop: S.m }}>
            <Field label="نام کاربری جدید (۳ تا ۲۰ کاراکتر)" value={name} onChangeText={setName} maxLength={20} autoCapitalize="none" />
            <View style={{ flexDirection: 'row-reverse' }}>
              <Btn label={busy ? '…' : 'ذخیره'} small onPress={saveName} disabled={busy} style={{ flex: 1, marginLeft: S.s }} />
              <Btn label="انصراف" small colors={G.dark} onPress={() => { setEditName(false); setErr(null); }} style={{ flex: 1 }} />
            </View>
          </View>
        ) : <Press onPress={() => { setName(a.profile!.username); setEditName(true); }} style={{ marginTop: S.s, minHeight: 44, justifyContent: 'center' }}><T s="✎ تغییر نام کاربری" style={{ color: C.cyan, fontSize: TS.small, textAlign: 'right' }} /></Press>
      ) : null}

      {sent ? (
        <View style={{ marginTop: S.m, padding: S.m, borderRadius: 14, backgroundColor: 'rgba(61,255,168,.08)', borderWidth: 1, borderColor: C.green + '55' }}>
          <T s={sent === 'reset' ? 'لینک تغییر رمز به ایمیلت فرستاده شد. لینک را روی همین گوشی باز کن تا رمز جدید را این‌جا وارد کنی.'
            : sent === 'upgrade' ? 'لینک تأیید به ایمیلت فرستاده شد. بعد از باز کردن لینک، حساب مهمانت با همه‌ی پیشرفت‌ها به ایمیل وصل می‌شود.'
              : 'حسابت ساخته شد! لینک تأیید را در ایمیلت باز کن، سپس وارد شو.'} style={{ fontSize: TS.small, textAlign: 'right', lineHeight: 22 }} />
          <View style={{ flexDirection: 'row-reverse', marginTop: S.s }}>
            {sent === 'confirm' ? <Btn label="ارسال دوباره" small colors={G.dark} onPress={async () => done(await a.resend(email), 'دوباره فرستاده شد')} style={{ flex: 1, marginLeft: S.s }} /> : null}
            <Btn label="باشه" small onPress={() => { setSent(null); if (sent === 'confirm') setMode('in'); }} style={{ flex: 1 }} />
          </View>
        </View>
      ) : !signedEmail ? (
        <View style={{ marginTop: S.m }}>
          <Segment value={mode} onChange={v => { setMode(v); setErr(null); }} items={[['up', a.isGuest ? 'ثبت ایمیل' : 'ثبت‌نام'], ['in', 'ورود'], ['forgot', 'فراموشی رمز']]} />
          <T s={mode === 'up' ? (a.isGuest ? 'با ثبت ایمیل، پیشرفت حساب مهمان حفظ می‌شود و روی هر گوشی وارد می‌شوی.' : 'حساب بساز تا پیشرفتت روی سرور ذخیره شود.')
            : mode === 'in' ? (a.isGuest ? 'ورود به حساب دیگر، حساب مهمان فعلی را کنار می‌گذارد.' : 'با ایمیل و رمز وارد شو.') : 'ایمیلت را وارد کن تا لینک تغییر رمز برایت ارسال شود.'}
            style={{ fontSize: TS.cap, color: C.dim, textAlign: 'right', marginVertical: S.s, lineHeight: 18 }} />
          <Field placeholder="ایمیل" value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" autoComplete="email" textContentType="emailAddress" style={{ textAlign: 'left', writingDirection: 'ltr' }} />
          {mode !== 'forgot' ? <Field placeholder="رمز عبور" value={pass} onChangeText={setPass} secureTextEntry autoCapitalize="none" textContentType={mode === 'up' ? 'newPassword' : 'password'} style={{ textAlign: 'left', writingDirection: 'ltr' }} /> : null}
          {mode === 'up' ? <Field placeholder="تکرار رمز عبور" value={pass2} onChangeText={setPass2} secureTextEntry autoCapitalize="none" style={{ textAlign: 'left', writingDirection: 'ltr' }} /> : null}
          {err ? <T s={err} style={{ color: C.red, fontSize: TS.small, textAlign: 'right', marginBottom: S.s }} /> : null}
          <Btn label={busy ? 'لطفاً صبر کن…' : mode === 'up' ? (a.isGuest ? 'ثبت ایمیل و حفظ پیشرفت' : 'ساخت حساب') : mode === 'in' ? 'ورود' : 'ارسال لینک'} small onPress={submit} disabled={busy} colors={mode === 'in' ? G.primary : G.green} />
          {!a.uid ? <Btn label="ادامه به‌عنوان مهمان" small colors={G.dark} style={{ marginTop: S.s }} onPress={async () => { setBusy(true); try { await a.ensure(); toast('به‌عنوان مهمان وارد شدی', 'ok'); } catch { toast('اتصال برقرار نشد', 'err'); } finally { setBusy(false); } }} /> : null}
        </View>
      ) : (err ? <T s={err} style={{ color: C.red, fontSize: TS.small, textAlign: 'right', marginTop: S.s }} /> : null)}

      {a.uid ? (
        <Btn label={sureOut ? (a.isGuest ? 'پیشرفت مهمان از دست می‌رود! دوباره بزن' : 'مطمئنی؟ دوباره بزن') : 'خروج از حساب'} small colors={G.red} style={{ marginTop: S.m }}
          onPress={async () => { if (!sureOut) { setSureOut(true); return; } setSureOut(false); await a.signOut(); toast('از حساب خارج شدی', 'ok'); }} />
      ) : null}
    </Panel>
  );
}

export function RecoveryModal({ toast }: { toast: (m: string, k?: string) => void }) {
  const a = useAuth();
  const [p1, setP1] = useState(''); const [p2, setP2] = useState(''); const [err, setErr] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  const save = async () => {
    if (p1.length < 6) { setErr('رمز عبور حداقل ۶ کاراکتر'); return; }
    if (p1 !== p2) { setErr('تکرار رمز یکسان نیست'); return; }
    setBusy(true); const r = await a.setNewPassword(p1); setBusy(false);
    if (!r.ok) { setErr(r.error); return; } toast('رمز عبور تغییر کرد', 'ok');
  };
  return (
    <Modal onClose={a.endRecovery} accent={C.cyan}>
      <View style={{ padding: S.l }}>
        <T s="رمز عبور جدید" style={{ fontFamily: F.title, fontSize: 20, textAlign: 'center', marginBottom: S.m }} />
        <Field placeholder="رمز جدید" value={p1} onChangeText={setP1} secureTextEntry autoCapitalize="none" style={{ textAlign: 'left', writingDirection: 'ltr' }} />
        <Field placeholder="تکرار رمز جدید" value={p2} onChangeText={setP2} secureTextEntry autoCapitalize="none" style={{ textAlign: 'left', writingDirection: 'ltr' }} />
        {err ? <T s={err} style={{ color: C.red, fontSize: TS.small, textAlign: 'right', marginBottom: S.s }} /> : null}
        <Btn label={busy ? '…' : 'ذخیره'} onPress={save} disabled={busy} />
        <Btn label="بعداً" small colors={G.dark} onPress={a.endRecovery} style={{ marginTop: S.s }} />
      </View>
    </Modal>
  );
}
