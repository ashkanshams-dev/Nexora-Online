import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/bomb_game.dart';

/// NEXORA Bomb Arena: 2-4 bombers, crates, power-ups and traps; bots offline, host-authoritative online.
Widget buildBombArenaGame(GameLaunch launch) => BombGame(launch: launch);
