import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/golf_game.dart';

/// NEXORA Mini Golf: 9 holes (bumpers, sand, water, windmills), 2-4 players, bots offline, turn-based online.
Widget buildMiniGolfGame(GameLaunch launch) => GolfGame(launch: launch);
