import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/spy_game.dart';

/// NEXORA Spy & Mafia: clue-and-vote social deduction for 4-8 players, bots offline, turn-based online.
Widget buildSpyMafiaGame(GameLaunch launch) => SpyGameView(launch: launch);
