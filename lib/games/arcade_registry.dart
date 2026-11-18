import 'package:flutter/material.dart';

import 'core/game_contract.dart';
import 'bomb_arena/bomb_arena_entry.dart';
import 'kart_racing/kart_racing_entry.dart';
import 'obstacle_race/obstacle_race_entry.dart';

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
];
