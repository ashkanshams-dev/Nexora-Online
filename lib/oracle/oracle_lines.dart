// Oracle lines used by result screens — port of the exports in src/oracle/Oracle.tsx.
import 'dart:math' as math;

import '../game/assets.dart';

String oracleImg(String mood) => ORACLE[mood] ?? ORACLE['idle']!;

const TIPS = [
  'از دیواره‌ها برای ضربه‌ی کمانه‌ای استفاده کن؛ دروازه‌بان‌ها انتظارش رو ندارن.',
  'همیشه قدرت کامل لازم نیست؛ ضربه‌ی متوسط توپ رو کنترل‌شده‌تر می‌بره.',
  'یک دیسک رو جلوی دروازه نگه دار تا ضدحمله‌ها رو خنثی کنه.',
  'قبل از شوت، پیش‌نمایش مسیر رو نگاه کن؛ دیسک‌های دقیق‌تر مسیر بلندتری نشون می‌دن.',
  'با ضربه‌ی اول نمی‌شه گل زد؛ اول توپ رو به موقعیت خوب برسون.',
  'اگر زمان نوبت کمه، یک ضربه‌ی امن دفاعی بهتر از از دست دادن نوبته.',
];
final _r = math.Random();
String tip() => TIPS[_r.nextInt(TIPS.length)];

({String mood, String text}) resultLine(String out) {
  if (out == 'victory') {
    return (mood: _r.nextBool() ? 'joy' : 'laugh', text: const ['عالی بود کاپیتان! 🏆', 'چه بردی! کهکشان به احترامت ایستاده. ✨', 'همین‌طوری ادامه بده، قهرمان! 🔥'][_r.nextInt(3)]);
  }
  if (out == 'defeat') return (mood: 'calm', text: 'اشکالی نداره، دست بعدی مال ماست. 💙 نکته: ${tip()}');
  return (mood: 'content', text: 'مساوی! فقط یک ضربه تا برد فاصله داشتیم. 🤝');
}
