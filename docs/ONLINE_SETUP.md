# آنلاین کردن NEXORA (Supabase + LiveKit)

این نسخه کاملاً آفلاین کار می‌کند. همه‌ی منطق‌ها پشت «درز»های مشخص نوشته شده‌اند تا آنلاین کردن یعنی **پیاده‌سازی همان رابط‌ها**، نه بازنویسی.

## ۱. درزهای آماده
| بخش | فایل | کار برای آنلاین |
|---|---|---|
| بک‌اند کلی | `lib/core/backend/backend_gateway.dart` | یک `SupabaseBackend implements BackendGateway` بساز و در `backendProvider` جایگزین `OfflineBackend` کن. |
| هویت و پیشرفت | `lib/core/profile/profile_service.dart` | بعد از ورود، `award()` رویداد خام را با `submitXpEvent` به سرور بفرستد؛ مقدار XP/سکه از `profiles` خوانده شود (سرور منبع حقیقت، P21). |
| ذخیره‌ی محلی | `lib/core/storage/local_store.dart` | همان کلیدها کش آفلاین می‌مانند؛ لایه‌ی sync هنگام اتصال آن‌ها را push/pull می‌کند. |
| Nova / Orbit / Social | `lib/worlds/*/data/*_repository.dart` | هر دنیا یک `XxxRepository` انتزاعی دارد؛ نسخه‌ی `SupabaseXxxRepository` بنویس (جدول‌ها در migration هست). |
| ORACLE | `lib/worlds/oracle_core/core/` | `RemoteOracleEngine` را با Edge Function مدل زبانی کامل کن؛ موتور آفلاین fallback می‌ماند. |
| بازی‌ها | `lib/games/<id>/core/` | هسته‌ها خالص Dart و قطعی‌اند؛ برای آنلاین، همان منطق در Edge Function اجرا می‌شود (نمونه: `supabase/functions/submit_shot`). |
| تماس | Orbit Network | `liveKitToken()` توکن کوتاه‌عمر از Edge Function می‌گیرد؛ پکیج `livekit_client` اضافه شود. |

## ۲. مراحل Supabase
```bash
supabase login --token "$SUPABASE_ACCESS_TOKEN"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push                       # اجرای supabase/migrations/*.sql
supabase functions deploy submit_shot
supabase secrets set LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... LLM_API_KEY=...
```
سپس در `pubspec.yaml`:
```yaml
  supabase_flutter: ^2.8.0
  livekit_client: ^2.3.0
```
و آدرس/anon key را با `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` در GitHub Actions بده (هیچ secret داخل کد نباشد، P19).

## ۳. GitHub Actions
`.github/workflows/android.yml` با هر push یک APK می‌سازد (artifact به نام `NEXORA-apk`). برای انتشار در Google Play: keystore را با `gh secret set ANDROID_KEYSTORE_B64` اضافه کن و `flutter build appbundle` را فعال کن.

## ۴. چیزهایی که فقط بعد از آنلاین فعال می‌شوند (در اپ با برچسب صادقانه مشخص‌اند)
ورود ایمیل/گوگل و همگام‌سازی، کاربران واقعی و دوستان، چت با دیگران، تماس صوتی/تصویری، بازی آنلاین و Matchmaking، رتبه‌بندی جهانی، پاسخ‌های مدل زبانی ORACLE و ورودی صوتی.

## ۵. لینک‌های ایمیل (تأیید ثبت‌نام، لینک ورود، بازیابی رمز)
- اپ همه‌ی درخواست‌ها را با `emailRedirectTo` / `redirectTo` = `nexora://auth-callback?flow=<signup|magiclink|recovery|email_change>` می‌فرستد (`lib/core/online/auth_link.dart`).
- اندروید: intent-filter برای `nexora://auth-callback` (VIEW/DEFAULT/BROWSABLE) کنار `nexora://t` در `.github/workflows/android.yml` اضافه می‌شود.
- اپ لینک را با deep linking خود Flutter → GoRouter به `/auth/callback` می‌برد و کد PKCE را با `exchangeCodeForSession` به نشست تبدیل می‌کند (شروع سرد و گرم هر دو). `detectSessionInUri` خاموش است تا کد یک‌بارمصرف دوبار مصرف نشود.
- پروژه‌ی eisstodgncimypdawisy: `uri_allow_list` شامل `nexora://auth-callback` و `nexora://auth-callback**` است (ورودی‌های قبلی `nexora://**,nexora://login-callback,exp://**,exps://**` دست‌نخورده). `site_url` = `nexora://login-callback` عمداً تغییر نکرد (پیش‌فرض اپ‌های Expo/Godot).
- قالب ایمیل‌ها `{{ .ConfirmationURL }}` دارند. تغییر قالب در پلن رایگان بدون SMTP اختصاصی ممکن نیست؛ بنابراین ایمیل لینک ورود کد ۶ رقمی (`{{ .Token }}`) ندارد تا SMTP تنظیم شود.
- `mailer_autoconfirm` فعلاً `true` است: ثبت‌نام بدون ایمیل تأیید وارد می‌شود. برای اجباری کردن تأیید ایمیل آن را `false` کنید (روی اپ‌های Expo/Godot هم اثر دارد).
- لینک تأیید باید روی همان گوشی‌ای باز شود که ثبت‌نام از آن انجام شده (PKCE)؛ در غیر این صورت ایمیل تأیید می‌شود و اپ می‌گوید با رمز وارد شو.
