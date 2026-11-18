import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/pool8_game.dart';

/// NEXORA 8 Ball Pool Blitz: classic 8-ball rules with a shot clock, bot offline, turn-by-turn online.
Widget buildPool8Game(GameLaunch launch) => Pool8Game(launch: launch);
