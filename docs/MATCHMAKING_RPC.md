# مستندات Matchmaking و RPCهای بازی آنلاین

**نسخه migration:** `20261118000000_g_matchmaking_hardening.sql`  
**Commit پیاده‌سازی:** `e17bb42`  
**پروژه:** NEXORA Games / Supabase

این سند قرارداد فعلی matchmaking را برای backend، Flutter client و عملیات migration توضیح می‌دهد. مرجع نهایی رفتار سرور، migrationهای SQL و امضای RPCها هستند.

## 1. معماری کلی

Matchmaking بر پایه‌ی roomهای quick موجود در `nx_rooms` ساخته شده است. هر درخواست جدید ابتدا در جدول durable به نام `nx_matchmaking_requests` ثبت می‌شود، سپس سرور یک room سازگار را با قفل PostgreSQL انتخاب می‌کند یا room جدید می‌سازد.

```text
Flutter OnlineLobbyPage
        |
        | nx_quick_match(...)
        v
nx_matchmaking_requests  ---- idempotency / lifecycle / audit
        |
        | select compatible lobby with FOR UPDATE SKIP LOCKED
        v
nx_rooms + nx_room_players
        |
        | full room
        v
nx_matches
```

RPCهای جدید `SECURITY DEFINER` هستند و با `search_path = public` اجرا می‌شوند. کاربر باید session معتبر داشته باشد؛ شناسه‌ی بازیکن از `auth.uid()` گرفته می‌شود و از client دریافت نمی‌شود.

## 2. جدول `nx_matchmaking_requests`

این جدول وضعیت durable هر درخواست quick match را نگه می‌دارد.

| ستون | نوع | توضیح |
|---|---|---|
| `id` | `uuid` | شناسه‌ی سروری درخواست، با `gen_random_uuid()` |
| `user_id` | `uuid` | کاربر صاحب درخواست؛ از `auth.uid()` پر می‌شود |
| `idem_key` | `text` | کلید idempotency کاربر، حداکثر ۹۶ کاراکتر مؤثر |
| `game` | `text` | شناسه‌ی بازی، مانند `finger_soccer` یا `carrom` |
| `seats` | `integer` | تعداد جایگاه مورد نیاز، بین ۲ و ۱۲ |
| `rating_min` | `integer` | حداقل rating قابل قبول |
| `rating_max` | `integer` | حداکثر rating قابل قبول |
| `max_ping_ms` | `integer` | بیشترین ping قابل قبول، بین ۲۰ و ۲۰۰۰ میلی‌ثانیه |
| `region` | `text` | region مورد نظر؛ مقدار معمول `auto` است |
| `status` | `text` | یکی از `searching`, `matched`, `cancelled`, `timed_out`, `failed` |
| `room_id` | `uuid` nullable | room quick اختصاص‌داده‌شده به درخواست |
| `created_at` | `timestamptz` | زمان ساخت درخواست |
| `updated_at` | `timestamptz` | آخرین تغییر وضعیت یا room |
| `cancelled_at` | `timestamptz` nullable | زمان cancel موفق |

### Constraintها و indexها

- کلید اصلی: `id`
- یکتا بودن درخواست تکراری: `(user_id, idem_key)`
- هر کاربر فقط یک درخواست با وضعیت `searching` فعال دارد؛ این موضوع با unique partial index روی `user_id` اعمال می‌شود.
- جست‌وجوی queue با index جزئی `(game, seats, region, status, created_at)` انجام می‌شود.
- RLS فعال است و policy خواندن فقط رکوردهای متعلق به `auth.uid()` را برای role `authenticated` مجاز می‌کند. RPCها از طریق `SECURITY DEFINER` عملیات خود را انجام می‌دهند.

> client نباید مستقیماً در جدول insert/update انجام دهد. ایجاد، cancel و تغییر وضعیت فقط از طریق RPCهای تعریف‌شده انجام می‌شود.

## 3. وضعیت‌های server-side

```text
searching ──(room کامل شد)──> matched
searching ──(cancel RPC)────> cancelled
searching ──(exception)─────> failed
```

`timed_out` در enum قراردادی جدول برای worker یا job آینده در نظر گرفته شده است. در مسیر فعلی Flutter، timeout سی‌ثانیه‌ای با `nx_cancel_matchmaking` به cancel سروری ختم می‌شود؛ بنابراین request معمولاً در سرور به `cancelled` می‌رسد، نه `timed_out`.

## 4. RPC: `nx_quick_match`

### امضا

```sql
public.nx_quick_match(
  p_game text,
  p_seats integer,
  p_rating_min integer default 0,
  p_rating_max integer default 3000,
  p_max_ping_ms integer default 250,
  p_region text default 'auto',
  p_idem_key text default null
) returns jsonb
```

### دسترسی

- `anon`: مجاز طبق grant فعلی، اما بدون session معتبر RPC با `not signed in` شکست می‌خورد.
- `authenticated`: مجاز.
- `service_role`: مجاز برای workerها و عملیات server-side.

### اعتبارسنجی

RPC موارد زیر را قبل از ایجاد request بررسی می‌کند:

1. وجود session و `auth.uid()`.
2. غیرخالی بودن `p_idem_key`.
3. معتبر بودن region با الگوی `[a-zA-Z0-9_-]{2,16}`.
4. شناخته‌شدن بازی توسط `nx_game_bounds(p_game)`.
5. قرار داشتن `p_seats` در محدوده‌ی min/max همان بازی.
6. غیرمنفی بودن rating و بزرگ‌تر یا مساوی بودن `p_rating_max` نسبت به `p_rating_min`.
7. قرار داشتن `p_max_ping_ms` در بازه‌ی ۲۰ تا ۲۰۰۰.

### رفتار idempotent

RPC ابتدا `(auth.uid(), p_idem_key)` را جست‌وجو می‌کند. اگر همان درخواست قبلاً ثبت شده باشد، همان `request_id`، `room_id` و `status` را برمی‌گرداند و room جدید نمی‌سازد.

اگر کاربر با idempotency key متفاوت، یک درخواست `searching` فعال داشته باشد، همان درخواست فعال برگردانده می‌شود. این رفتار از duplicate search و چند room هم‌زمان برای یک کاربر جلوگیری می‌کند.

### الگوریتم انتخاب room

1. roomهای `nx_rooms` با شرایط زیر بررسی می‌شوند:
   - `game = p_game`
   - `status = 'lobby'`
   - `quick = true`
   - `is_private = false`
   - `seats = p_seats`
   - room ظرفیت خالی داشته باشد
   - region سازگار باشد؛ `auto` با همه‌ی regionها سازگار است
   - بازه‌ی rating room با بازه‌ی درخواست overlap داشته باشد
   - `max_ping_ms` room از سقف درخواست بیشتر نباشد
2. اولین room با `created_at` قدیمی‌تر انتخاب می‌شود.
3. انتخاب با `FOR UPDATE SKIP LOCKED` انجام می‌شود تا دو درخواست concurrent یک room را به‌صورت نادرست انتخاب نکنند.
4. اگر room سازگار وجود نداشته باشد، با `nx_create_room` یک quick room جدید ساخته می‌شود و معیارهای matchmaking در `settings.matchmaking` ذخیره می‌شوند.
5. اگر room بعد از join کامل شود، `nx_start_match_quick` اجرا و match ساخته می‌شود.
6. در صورت کامل شدن room، درخواست‌های searching متصل به همان room به `matched` تغییر می‌کنند.

### نمونه‌ی request از Supabase Flutter

```dart
final result = await games.rpc(
  'nx_quick_match',
  params: <String, dynamic>{
    'p_game': 'finger_soccer',
    'p_seats': 2,
    'p_rating_min': 900,
    'p_rating_max': 1200,
    'p_max_ping_ms': 250,
    'p_region': 'auto',
    'p_idem_key': stableRequestKey,
  },
);
```

`stableRequestKey` باید تا زمان دریافت پاسخ نهایی یا cancel ثابت بماند. در retry شبکه، کلید جدید تولید نکنید؛ استفاده از همان کلید باعث می‌شود RPC نتیجه‌ی درخواست قبلی را برگرداند.

### پاسخ ایجاد درخواست یا پیوستن به room

نمونه‌ی پاسخ وقتی هنوز حریف کافی نیست:

```json
{
  "room_id": "8e8c2a1e-3d70-4f8c-9f36-000000000001",
  "code": "Q7K2M9P4",
  "seat": 0,
  "status": "lobby",
  "request_id": "3c3e4b9b-4ec1-44da-8888-000000000001",
  "idempotent": false
}
```

نمونه‌ی پاسخ وقتی room کامل و match ساخته شده است:

```json
{
  "room_id": "8e8c2a1e-3d70-4f8c-9f36-000000000001",
  "match_id": "4d5f6a7b-8c90-4d12-aaaa-000000000001",
  "seed": 18374621,
  "request_id": "3c3e4b9b-4ec1-44da-8888-000000000001",
  "status": "matched",
  "idempotent": false
}
```

نمونه‌ی پاسخ retry idempotent:

```json
{
  "request_id": "3c3e4b9b-4ec1-44da-8888-000000000001",
  "room_id": "8e8c2a1e-3d70-4f8c-9f36-000000000001",
  "status": "searching",
  "idempotent": true
}
```

در پاسخ idempotent، ممکن است `room_id` وجود داشته باشد ولی `match_id` در payload RPC برنگردد. client باید room را refresh کند و وضعیت `nx_rooms.status` و `nx_rooms.match_id` را از سرور بخواند.

## 5. RPC: `nx_cancel_matchmaking`

### امضا

```sql
public.nx_cancel_matchmaking(p_idem_key text) returns jsonb
```

### رفتار

- درخواست را فقط برای `auth.uid()` فعلی پیدا می‌کند.
- اگر request پیدا نشود، پاسخ idempotent زیر را می‌دهد:

```json
{"ok": true, "status": "cancelled", "already": true}
```

- اگر request قبلاً `matched` شده باشد، آن را cancel نمی‌کند تا client به‌صورت تصادفی match فعال را ترک نکند:

```json
{
  "ok": false,
  "status": "matched",
  "room_id": "..."
}
```

- اگر room هنوز در وضعیت `lobby` باشد، `nx_leave_room` روی آن اجرا می‌شود.
- سپس request به `cancelled` تغییر می‌کند و `cancelled_at` ثبت می‌شود.

### نمونه‌ی Flutter

```dart
final result = await games.rpc(
  'nx_cancel_matchmaking',
  params: <String, dynamic>{'p_idem_key': stableRequestKey},
);

if (result['status'] == 'matched') {
  // قبل از leave کردن، room/match را refresh کنید.
} else {
  // cancel موفق یا قبلاً cancel‌شده.
}
```

## 6. RPCهای legacy و ارتباط آن‌ها

### `nx_quick(p_game, p_seats)`

این RPC قدیمی برای compatibility باقی مانده است. کلاینت جدید باید از `nx_quick_match` استفاده کند، چون `nx_quick` فاقد موارد زیر است:

- durable request record
- idempotency key
- rating/ping/region contract
- cancel اختصاصی matchmaking
- status durable برای retry

`nx_quick` همچنان توسط مسیرهای قدیمی قابل استفاده است و از roomهای quick و قفل `FOR UPDATE SKIP LOCKED` استفاده می‌کند.

### RPCهای room که matchmaking به آن‌ها تکیه دارد

| RPC | کاربرد |
|---|---|
| `nx_create_room` | ساخت room quick با settings matchmaking |
| `nx_join_room` | ورود اتمیک به room و تخصیص seat |
| `nx_leave_room` | ترک room و بستن room خالی؛ در match فعال می‌تواند forfeit کند |
| `nx_start_match_quick` | ساخت match وقتی quick room کامل شده است |
| `nx_game_bounds` | دریافت min/max بازیکن مجاز برای بازی |

## 7. مدل client-side در Flutter

فایل مدل:

```text
lib/worlds/arcade/online/matchmaking_state.dart
```

enum وضعیت‌ها:

```dart
enum MatchmakingPhase {
  idle,
  searching,
  reconnecting,
  matched,
  cancelled,
  timedOut,
  failed,
}
```

ویژگی‌های مهم:

- `active`: فقط `searching` و `reconnecting` فعال محسوب می‌شوند.
- `retryable`: وضعیت‌های `cancelled`، `timedOut` و `failed` قابل retry هستند.
- `start()`: attempt را یک واحد افزایش می‌دهد.
- `resumeSearching()`: بعد از reconnect به searching برمی‌گردد بدون افزایش attempt.
- `matched(roomId)`: شناسه‌ی room را ذخیره می‌کند.
- `timeout()`, `cancel()` و `fail(message)`: انتقال‌های terminal هستند.

در `OnlineLobbyPage`، timer سی‌ثانیه‌ای صرفاً watchdog کلاینت است. منبع حقیقت match همیشه RPC و جدول‌های سرور هستند؛ پس از reconnect یا timeout، client باید room را refresh کند و فقط در صورت پاسخ server تصمیم نهایی بگیرد.

## 8. خطاهای قراردادی

| پیام سرور | علت معمول | رفتار client |
|---|---|---|
| `not signed in` | session وجود ندارد | انتقال به auth یا تلاش برای ساخت session |
| `idempotency key required` | کلید خالی است | ساخت key پایدار و retry |
| `unknown game` | game در `nx_game_bounds` ثبت نشده | نمایش خطای configuration |
| `invalid player count` | تعداد بازیکن خارج از bounds بازی است | اصلاح seats در UI |
| `invalid rating range` | min بیشتر از max یا مقدار منفی | اصلاح contract |
| `invalid ping` | خارج از ۲۰ تا ۲۰۰۰ | اصلاح ping budget |
| `invalid region` | region با فرمت مجاز سازگار نیست | استفاده از region معتبر یا `auto` |
| `room full` | room بین select و join پر شده است | درخواست جدید با همان key یا retry server-side |
| `room already started` | room قبل از join شروع شده است | refresh وضعیت room |

## 9. Migration و استقرار

فایل migration باید از طریق migration pipeline همان پروژه‌ی **Games Supabase** اعمال شود:

```text
supabase/games/migrations/20261118000000_g_matchmaking_hardening.sql
```

ترتیب لازم:

1. migrationهای پایه‌ی games شامل `nx_rooms`, `nx_room_players`, `nx_matches`, `nx_game_bounds` و RPCهای room قبلی باید قبلاً اعمال شده باشند.
2. migration جدید اجرا شود.
3. وجود table، index، RLS policy و دو RPC جدید بررسی شود.
4. بعد از deploy، Flutter client جدید منتشر شود؛ client قدیمی همچنان با `nx_quick` کار می‌کند.

### بررسی‌های SQL پیشنهادی پس از deploy

```sql
select to_regclass('public.nx_matchmaking_requests');

select routine_name, routine_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('nx_quick_match', 'nx_cancel_matchmaking');

select indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'nx_matchmaking_requests';
```

برای خواندن operational data در ابزارهای داخلی، queryها را محدود و صفحه‌بندی‌شده اجرا کنید؛ جدول request ممکن است در production بزرگ شود.

## 10. سناریوهای تست پذیرش

1. دو کاربر با یک `game` و `seats` سازگار، هرکدام با idempotency key جدا، باید به یک quick room برسند.
2. تکرار همان RPC با همان `(user_id, idem_key)` نباید room یا request جدید بسازد.
3. اجرای هم‌زمان چند request برای یک کاربر نباید بیش از یک request `searching` ایجاد کند.
4. یک request با region ناسازگار نباید به room region مشخص دیگری join شود.
5. rating rangeهای بدون overlap نباید با هم match شوند.
6. ping room بالاتر از `max_ping_ms` نباید انتخاب شود.
7. cancel قبل از کامل شدن room باید request را `cancelled` کند و room خالی را ببندد.
8. cancel بعد از match باید پاسخ `status = matched` بدهد و match را به‌صورت تصادفی forfeit نکند.
9. reconnect کلاینت باید همان idempotency key را حفظ کند و وضعیت request/room را refresh کند.
10. بعد از کامل شدن room، `nx_rooms.match_id` و status باید برای همه‌ی بازیکنان قابل مشاهده و قابل refresh باشد.

## 11. محدودیت‌های فعلی و مرحله‌ی بعد

- در client فعلی مقادیر پیش‌فرض `rating_min = 0`، `rating_max = 3000`، `max_ping_ms = 250` و `region = auto` ارسال می‌شوند. UI انتخاب region، ping probe واقعی و rating profile در مرحله‌ی بعد قابل اضافه شدن است.
- مقدار ping فعلاً contract و filter سروری است؛ اندازه‌گیری latency واقعی و multi-region routing هنوز جداگانه باید اضافه شود.
- transition خودکار `searching -> timed_out` در worker سرور وجود ندارد؛ timeout فعلی توسط Flutter watchdog و سپس RPC cancel انجام می‌شود.
- برای production، پاک‌سازی دوره‌ای requestهای قدیمی و metrics مربوط به queue wait time باید به job/monitoring متصل شود.
