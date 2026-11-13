// Account section (Settings / Welcome) + password-recovery modal — port of src/screens/Account.tsx.
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../i18n/i18n.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

bool emailOk(String e) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e.trim());

typedef Toast = void Function(String m, [String k]);

class Avatar extends StatelessWidget {
  final String? avatar, url;
  final double size;
  const Avatar({super.key, this.avatar, this.url, this.size = 48});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 2), color: hex('#050816')),
        alignment: Alignment.center,
        child: ClipOval(child: Img(url ?? discImg(avatar), w: size - 6, h: size - 6, fit: url != null ? BoxFit.cover : BoxFit.contain)),
      );
}

class Field extends StatelessWidget {
  final String? placeholder, label;
  final TextEditingController ctl;
  final bool secure, ltr;
  final int? maxLength;
  final TextInputType? keyboard;
  const Field({super.key, required this.ctl, this.placeholder, this.label, this.secure = false, this.ltr = false, this.maxLength, this.keyboard});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: SP.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (label != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: T(label!, style: fs(F.body, TY.cap, color: C.dim))),
          TextField(
            controller: ctl,
            obscureText: secure,
            maxLength: maxLength,
            keyboardType: keyboard,
            autocorrect: false,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: ltr ? TextAlign.left : TextAlign.right,
            style: fs(F.body, 14),
            decoration: InputDecoration(hintText: placeholder == null ? null : tr(placeholder!), counterText: '', isDense: true),
          ),
        ]),
      );
}

class AccountPanel extends StatefulWidget {
  final Toast toast;
  const AccountPanel({super.key, required this.toast});
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  String mode = 'up';
  final email = TextEditingController(), pass = TextEditingController(), pass2 = TextEditingController(), name = TextEditingController();
  bool editName = false, busy = false, sureOut = false;
  String? sent, err;

  bool done(Res r, [String? okMsg]) {
    if (!r.ok) {
      setState(() => err = r.error ?? 'خطا');
      buzz(Buzz.heavy);
      return false;
    }
    setState(() => err = null);
    if (okMsg != null) widget.toast(okMsg, 'ok');
    buzz(Buzz.success);
    return true;
  }

  Future<void> submit() async {
    final a = Auth.I;
    setState(() => err = null);
    if (!emailOk(email.text)) return setState(() => err = 'ایمیل معتبر نیست');
    if (mode != 'forgot' && pass.text.length < 6) return setState(() => err = 'رمز عبور حداقل ۶ کاراکتر');
    if (mode == 'up' && pass.text != pass2.text) return setState(() => err = 'تکرار رمز عبور یکسان نیست');
    setState(() => busy = true);
    try {
      if (mode == 'forgot') {
        if (done(await a.resetPassword(email.text))) setState(() => sent = 'reset');
      } else if (mode == 'in') {
        if (done(await a.signIn(email.text, pass.text), 'وارد شدی')) pass.clear();
      } else if (a.uid != null && a.isGuest) {
        if (done(await a.upgrade(email.text, pass.text))) setState(() => sent = 'upgrade');
      } else {
        final r = await a.signUp(email.text, pass.text);
        if (done(r)) setState(() => sent = r.info == 'confirm' ? 'confirm' : null);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Auth.I,
      builder: (context, _) {
        final a = Auth.I;
        if (!a.configured) return const SizedBox.shrink();
        final prof = a.profile;
        final signedEmail = a.uid != null && !a.isGuest;
        return Padding(
          padding: const EdgeInsets.only(bottom: SP.s + 2),
          child: Panel(
            accent: C.cyan,
            pad: const EdgeInsets.all(SP.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(textDirection: TextDirection.rtl, children: [
                prof != null ? Avatar(avatar: (prof['equipped_disc'] ?? prof['avatar']) as String?, url: prof['avatar_url'] as String?) : Img(UI2['c_profile'], w: 44, h: 44),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: SP.m),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      T('حساب آنلاین', style: fs(F.bold, 15)),
                      T(a.uid == null ? 'وارد نشده‌ای' : a.isGuest ? 'مهمان · ${prof?['username'] ?? ''}' : '${a.email} · ${prof?['username'] ?? ''}', n: 1, style: fs(F.body, TY.cap, color: C.dim)),
                    ]),
                  ),
                ),
                if (prof != null) T('سطح ${fa(ri(prof, 'level'))}', style: fs(F.bold, TY.cap, color: C.gold)),
              ]),
              if (prof != null)
                editName
                    ? Padding(
                        padding: const EdgeInsets.only(top: SP.m),
                        child: Column(children: [
                          Field(ctl: name, label: 'نام کاربری جدید (۳ تا ۲۰ کاراکتر)', maxLength: 20),
                          Row(textDirection: TextDirection.rtl, children: [
                            Expanded(
                              child: Btn(label: busy ? '…' : 'ذخیره', small: true, disabled: busy, onPress: () async {
                                setState(() => busy = true);
                                final r = await a.setUsername(name.text);
                                setState(() => busy = false);
                                if (done(r, 'نام کاربری تغییر کرد')) setState(() => editName = false);
                              }),
                            ),
                            const SizedBox(width: SP.s),
                            Expanded(child: Btn(label: 'انصراف', small: true, colors: G.dark, onPress: () => setState(() => (editName = false, err = null)))),
                          ]),
                        ]),
                      )
                    : Press(
                        onPress: () => setState(() {
                          name.text = prof['username'] as String? ?? '';
                          editName = true;
                        }),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: T('✎ تغییر نام کاربری', align: TextAlign.right, style: fs(F.body, TY.small, color: C.cyan))),
                      ),
              if (sent != null)
                Container(
                  margin: const EdgeInsets.only(top: SP.m),
                  padding: const EdgeInsets.all(SP.m),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(61, 255, 168, .08), border: Border.all(color: C.green.withValues(alpha: .33))),
                  child: Column(children: [
                    T(
                        sent == 'reset'
                            ? 'لینک تغییر رمز به ایمیلت فرستاده شد. لینک را روی همین گوشی باز کن تا رمز جدید را این‌جا وارد کنی.'
                            : sent == 'upgrade'
                                ? 'لینک تأیید به ایمیلت فرستاده شد. بعد از باز کردن لینک، حساب مهمانت با همه‌ی پیشرفت‌ها به ایمیل وصل می‌شود.'
                                : 'حسابت ساخته شد! لینک تأیید را در ایمیلت باز کن، سپس وارد شو.',
                        align: TextAlign.right,
                        style: fs(F.body, TY.small, height: 1.6)),
                    const SizedBox(height: SP.s),
                    Row(textDirection: TextDirection.rtl, children: [
                      if (sent == 'confirm') ...[
                        Expanded(child: Btn(label: 'ارسال دوباره', small: true, colors: G.dark, onPress: () async => done(await a.resend(email.text), 'دوباره فرستاده شد'))),
                        const SizedBox(width: SP.s),
                      ],
                      Expanded(
                        child: Btn(label: 'باشه', small: true, onPress: () => setState(() {
                          if (sent == 'confirm') mode = 'in';
                          sent = null;
                        })),
                      ),
                    ]),
                  ]),
                )
              else if (!signedEmail)
                Padding(
                  padding: const EdgeInsets.only(top: SP.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Segment<String>(
                      value: mode,
                      onChange: (v) => setState(() => (mode = v, err = null)),
                      items: [('up', a.isGuest ? 'ثبت ایمیل' : 'ثبت‌نام'), ('in', 'ورود'), ('forgot', 'فراموشی رمز')],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: SP.s),
                      child: T(
                          mode == 'up'
                              ? (a.isGuest ? 'با ثبت ایمیل، پیشرفت حساب مهمان حفظ می‌شود و روی هر گوشی وارد می‌شوی.' : 'حساب بساز تا پیشرفتت روی سرور ذخیره شود.')
                              : mode == 'in'
                                  ? (a.isGuest ? 'ورود به حساب دیگر، حساب مهمان فعلی را کنار می‌گذارد.' : 'با ایمیل و رمز وارد شو.')
                                  : 'ایمیلت را وارد کن تا لینک تغییر رمز برایت ارسال شود.',
                          align: TextAlign.right,
                          style: fs(F.body, TY.cap, color: C.dim, height: 1.5)),
                    ),
                    Field(ctl: email, placeholder: 'ایمیل', ltr: true, keyboard: TextInputType.emailAddress),
                    if (mode != 'forgot') Field(ctl: pass, placeholder: 'رمز عبور', secure: true, ltr: true),
                    if (mode == 'up') Field(ctl: pass2, placeholder: 'تکرار رمز عبور', secure: true, ltr: true),
                    if (err != null) Padding(padding: const EdgeInsets.only(bottom: SP.s), child: T(err!, align: TextAlign.right, style: fs(F.body, TY.small, color: C.red))),
                    Btn(
                      label: busy ? 'لطفاً صبر کن…' : mode == 'up' ? (a.isGuest ? 'ثبت ایمیل و حفظ پیشرفت' : 'ساخت حساب') : mode == 'in' ? 'ورود' : 'ارسال لینک',
                      small: true,
                      disabled: busy,
                      colors: mode == 'in' ? G.primary : G.green,
                      onPress: submit,
                    ),
                    if (a.uid == null)
                      Padding(
                        padding: const EdgeInsets.only(top: SP.s),
                        child: Btn(label: 'ادامه به‌عنوان مهمان', small: true, colors: G.dark, onPress: () async {
                          setState(() => busy = true);
                          try {
                            await a.ensure();
                            widget.toast('به‌عنوان مهمان وارد شدی', 'ok');
                          } catch (_) {
                            widget.toast('اتصال برقرار نشد', 'err');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        }),
                      ),
                  ]),
                )
              else if (err != null)
                Padding(padding: const EdgeInsets.only(top: SP.s), child: T(err!, align: TextAlign.right, style: fs(F.body, TY.small, color: C.red))),
              if (a.uid != null)
                Padding(
                  padding: const EdgeInsets.only(top: SP.m),
                  child: Btn(
                    label: sureOut ? (a.isGuest ? 'پیشرفت مهمان از دست می‌رود! دوباره بزن' : 'مطمئنی؟ دوباره بزن') : 'خروج از حساب',
                    small: true,
                    colors: G.red,
                    onPress: () async {
                      if (!sureOut) return setState(() => sureOut = true);
                      setState(() => sureOut = false);
                      await a.signOut();
                      widget.toast('از حساب خارج شدی', 'ok');
                    },
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class RecoveryCard extends StatefulWidget {
  final Toast toast;
  const RecoveryCard({super.key, required this.toast});
  @override
  State<RecoveryCard> createState() => _RecoveryCardState();
}

class _RecoveryCardState extends State<RecoveryCard> {
  final p1 = TextEditingController(), p2 = TextEditingController();
  String? err;
  bool busy = false;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(SP.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: T('رمز عبور جدید', style: fs(F.title, 20))),
          const SizedBox(height: SP.m),
          Field(ctl: p1, placeholder: 'رمز جدید', secure: true, ltr: true),
          Field(ctl: p2, placeholder: 'تکرار رمز جدید', secure: true, ltr: true),
          if (err != null) T(err!, align: TextAlign.right, style: fs(F.body, TY.small, color: C.red)),
          Btn(label: busy ? '…' : 'ذخیره', disabled: busy, onPress: () async {
            if (p1.text.length < 6) return setState(() => err = 'رمز عبور حداقل ۶ کاراکتر');
            if (p1.text != p2.text) return setState(() => err = 'تکرار رمز یکسان نیست');
            setState(() => busy = true);
            final r = await Auth.I.setNewPassword(p1.text);
            if (!context.mounted) return;
            setState(() => busy = false);
            if (!r.ok) return setState(() => err = r.error);
            widget.toast('رمز عبور تغییر کرد', 'ok');
            Navigator.of(context).pop();
          }),
          const SizedBox(height: SP.s),
          Btn(label: 'بعداً', small: true, colors: G.dark, onPress: () {
            Auth.I.endRecovery();
            Navigator.of(context).pop();
          }),
        ]),
      );
}
