import 'package:flutter/material.dart';

import 'core/game_contract.dart';
import 'kart_racing/kart_racing_entry.dart';

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
];
