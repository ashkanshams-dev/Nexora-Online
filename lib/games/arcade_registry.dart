import 'package:flutter/material.dart';

import 'core/game_contract.dart';
import 'bomb_arena/bomb_arena_entry.dart';
import 'kart_racing/kart_racing_entry.dart';
import 'obstacle_race/obstacle_race_entry.dart';
import 'pool8/pool8_entry.dart';
import 'mini_golf/mini_golf_entry.dart';
import 'basketball_battle/basketball_battle_entry.dart';
import 'spy_mafia/spy_mafia_entry.dart';

/// NEXORA ARCADE expansion (redesign-2): 20 new games ADDED next to the original nine (none replaced).
/// Multiplayer games: bots offline + online rooms / quick match / invites / tournaments on the games project.
/// Solo games: quick start, daily challenge, server-validated global boards.
final List<GameInfo> kArcadeGames = <GameInfo>[
  GameInfo(
    id: 'kart_racing',
    nameFa: 'مسابقه‌ی کارت',
    nameEn: 'Kart Racing',
    taglineFa: 'دریفت، توربو و آیتم‌های قدرتی',
    taglineEn: 'Drift, turbo and power-ups',
    rulesFa: 'ماشین خودکار گاز می‌دهد؛ با دکمه‌های چپ و راست فرمان بده. در پیچ‌ها دکمه‌ی دریفت را نگه دار تا جرقه‌ها '
        'آبی، نارنجی و بنفش شوند و با رها کردن توربو بگیر. از جعبه‌های رنگی آیتم بگیر: توربو، موشک هدایت‌شونده '
        '(به نفر جلویی)، سپر و لکه‌ی روغن. سکوهای نارنجی سرعت می‌دهند. ۳ دور؛ اولین نفر برنده است.',
    rulesEn: 'Your kart accelerates by itself; steer with the left/right buttons. Hold DRIFT through corners until the '
        'sparks turn blue, orange then purple and release for a mini-turbo. Item boxes give turbo, a homing missile '
        '(hits the racer ahead), a shield or an oil slick. Orange pads boost you. 3 laps; first across the line wins.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 4,
    supportsLocal: false,
    accent: const Color(0xFFFF7A1A),
    builder: buildKartRacingGame,
    supportsOnline: true,
    group: 4,
    isNew: true,
  ),
  GameInfo(
    id: 'obstacle_race',
    nameFa: 'مسابقه‌ی موانع',
    nameEn: 'Obstacle Race',
    taglineFa: 'حذف رقبا تا آخرین بازمانده',
    taglineEn: 'Last runner standing',
    rulesFa: 'دونده‌ها خودکار جلو می‌روند و صفحه مدام سریع‌تر بالا می‌رود. انگشتت را بکش تا به چپ و راست بروی و با دکمه‌ی پرش '
        'از روی چاله‌ها و میله‌های چرخان بپر. دروازه‌های متحرک را از شکاف رد کن و مراقب جعبه‌های سقوطی باش. '
        'افتادن در چاله یا عقب ماندن از پایین صفحه یعنی حذف. آخرین بازمانده برنده است.',
    rulesEn: 'Runners move on their own while the screen scrolls ever faster. Drag to steer and press JUMP to clear pits '
        'and spinning sweepers. Thread moving gates through the gap and dodge falling blocks. Falling into a pit or '
        'dropping off the bottom of the screen eliminates you. The last runner standing wins.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 4,
    supportsLocal: false,
    accent: const Color(0xFFFF4FA3),
    builder: buildObstacleRaceGame,
    supportsOnline: true,
    group: 4,
    isNew: true,
  ),
  GameInfo(
    id: 'bomb_arena',
    nameFa: 'میدان بمب',
    nameEn: 'Bomb Arena',
    taglineFa: 'بمب بگذار، تله بچین، رقبا را حذف کن',
    taglineEn: 'Bombs, traps and knock-outs',
    rulesFa: 'با جوی‌استیک حرکت کن و با دکمه‌ی بمب، بمب بگذار. انفجار به‌شکل صلیب پخش می‌شود، جعبه‌ها را می‌شکند و '
        'بمب‌های دیگر را هم منفجر می‌کند. از جعبه‌ها قدرت بگیر: برد بیشتر، بمب اضافه، سرعت و تله (تله حریف را چند لحظه بی‌حرکت می‌کند). '
        'به آتش نخور! آخرین نفر زنده برنده است؛ اگر زمان تمام شود، تعداد حذف‌ها تعیین می‌کند.',
    rulesEn: 'Move with the joystick and drop bombs with BOMB. Blasts spread in a cross, smash crates and chain other bombs. '
        'Crates hide power-ups: range, extra bomb, speed and traps (a trap freezes a rival for a moment). Stay out of the fire! '
        'Last bomber standing wins; if time runs out, knock-outs decide.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 4,
    supportsLocal: false,
    accent: const Color(0xFFFF4D3D),
    builder: buildBombArenaGame,
    supportsOnline: true,
    group: 4,
    isNew: true,
  ),
  GameInfo(
    id: 'pool8',
    nameFa: 'بیلیارد ۸ توپ',
    nameEn: '8 Ball Pool',
    taglineFa: 'بیلیارد سریع با ساعت ضربه',
    taglineEn: 'Fast 8-ball with a shot clock',
    rulesFa: 'قوانین کلاسیک ۸ توپ: اولین توپی که بعد از بریک وارد سوراخ شود گروه تو را تعیین می‌کند (ساده یا راه‌راه). '
        'همه‌ی توپ‌های گروهت را بینداز و در آخر توپ ۸ را. روی میز بکش تا نشانه بگیری و نوار قدرت سمت راست را پایین بکش و رها کن. '
        'هر ضربه ۲۰ ثانیه وقت دارد؛ تمام شدن وقت یا انداختن توپ سفید خطاست و حریف توپ را هرجا بخواهد می‌گذارد.',
    rulesEn: 'Classic 8-ball: the first ball potted after the break sets your group (solids or stripes). Clear your group, '
        'then sink the 8. Drag on the table to aim, pull the power bar on the right down and release to shoot. Every shot '
        'has a 20-second clock; running out of time or scratching is a foul and gives your rival ball-in-hand anywhere.',
    minPlayers: 2,
    maxPlayers: 2,
    defaultPlayers: 2,
    supportsLocal: false,
    accent: const Color(0xFF16C784),
    builder: buildPool8Game,
    supportsOnline: true,
    group: 1,
    isNew: true,
  ),
  GameInfo(
    id: 'mini_golf',
    nameFa: 'مینی گلف',
    nameEn: 'Mini Golf',
    taglineFa: '۹ حفره، مانع، آب و آسیاب بادی',
    taglineEn: '9 holes of bumpers, water and windmills',
    rulesFa: 'نوبتی بازی کنید: انگشتت را از توپ به عقب بکش و رها کن؛ هرچه بیشتر بکشی، ضربه محکم‌تر است. کسی که از حفره '
        'دورتر است اول می‌زند. شن توپ را کند می‌کند، آب یک ضربه جریمه دارد و پره‌های آسیاب می‌چرخند. هر حفره حداکثر ۷ '
        'ضربه. کمترین مجموع ضربه در ۹ حفره برنده است.',
    rulesEn: 'Take turns: pull back from anywhere and release to putt — the further you pull, the harder the shot. The '
        'player furthest from the cup goes first. Sand slows the ball, water costs a penalty stroke and windmill '
        'blades keep turning. 7 strokes max per hole. Fewest total strokes over 9 holes wins.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 2,
    supportsLocal: false,
    accent: const Color(0xFF7CFF7A),
    builder: buildMiniGolfGame,
    supportsOnline: true,
    group: 1,
    isNew: true,
  ),
  GameInfo(
    id: 'basketball_battle',
    nameFa: 'نبرد بسکتبال',
    nameEn: 'Basketball Battle',
    taglineFa: '۶۰ ثانیه پرتاب، بیشترین امتیاز می‌برد',
    taglineEn: '60-second shoot-out',
    rulesFa: 'همه هم‌زمان روی سبد خودشان پرتاب می‌کنند. انگشتت را رو به بالا بکش تا توپ پرتاب شود. پرتاب تمیز (سوییش) ۳ '
        'امتیاز و با برخورد به حلقه ۲ امتیاز دارد. سه گل پشت سر هم یعنی حالت آتشین و امتیاز دوبرابر تا اولین خطا. بعد '
        'از ۱۲ امتیاز سبد شروع به حرکت می‌کند. بیشترین امتیاز در ۶۰ ثانیه برنده است.',
    rulesEn: 'Everyone shoots at their own hoop at the same time. Swipe up to throw. A clean swish scores 3, off the rim 2. '
        'Three in a row sets you ON FIRE for double points until you miss. After 12 points the hoop starts sliding. '
        'Highest score after 60 seconds wins.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 2,
    supportsLocal: false,
    accent: const Color(0xFFFF8A2A),
    builder: buildBasketballBattleGame,
    supportsOnline: true,
    group: 1,
    isNew: true,
  ),
  GameInfo(
    id: 'spy_mafia',
    nameFa: 'جاسوس و مافیا',
    nameEn: 'Spy & Mafia',
    taglineFa: 'سرنخ بده، جاسوس را پیدا کن',
    taglineEn: 'Give clues, unmask the spy',
    rulesFa: 'همه به‌جز جاسوس مکان مخفی را می‌بینند (از ۷ نفر به بالا دو جاسوس/مافیا داریم). در دو دور، هر کس در نوبتش یکی '
        'از سه کلمه‌ی سرنخ را انتخاب می‌کند. مأمورها کلمه‌های مرتبط می‌گیرند و جاسوس باید با کلمه‌های بی‌ربط بلوف '
        'بزند. بعد همه به مشکوک‌ترین نفر رأی می‌دهند. اگر جاسوس لو برود هنوز می‌تواند با حدس درست مکان برنده شود؛ اگر '
        'لو نرود، جاسوس برنده است.',
    rulesEn: 'Everyone except the spy sees the secret location (with 7+ players there are two spies, the mafia). Over two '
        'rounds each player picks one of three clue words on their turn. Agents get words that fit; the spy gets '
        'unrelated words and must bluff. Then everyone votes for the most suspicious player. A caught spy can still '
        'win by naming the location; an uncaught spy wins outright.',
    minPlayers: 4,
    maxPlayers: 8,
    defaultPlayers: 5,
    supportsLocal: false,
    accent: const Color(0xFFB98CFF),
    builder: buildSpyMafiaGame,
    supportsOnline: true,
    group: 3,
    isNew: true,
  ),
];
