// Match-coach tip selection after a shot that did not touch the ball (kept tiny and occasional).
const SOFT = [
  'نزدیک بود! از دیواره کمانه بزن؛ زاویه‌ی بهتری به توپ می‌رسه. 🎯',
  'دیسکی رو انتخاب کن که مسیر مستقیم‌تری تا توپ داره. 👀',
  'پیش‌نمایش مسیر رو دنبال کن؛ نقطه‌ها نشون می‌دن دیسک کجا می‌ره.',
  'گاهی یک ضربه‌ی کوتاه برای بستن مسیر حریف بهترین حرکته. 🛡',
];
export function coachMiss(power: number, misses: number): string | null {
  if (power > .92) return 'قدرت خیلی زیاد بود؛ با کشیدن کمتر ضربه کنترل‌شده‌تر می‌شه. 💡';
  if (power < .18) return 'ضربه خیلی آروم بود؛ کمی بیشتر بکش تا به توپ برسی. 💪';
  if (misses % 2 === 1) return SOFT[Math.floor(Math.random() * SOFT.length)];
  return null;
}
