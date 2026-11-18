import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/obstacle_game.dart';

/// NEXORA Obstacle Race: last runner standing on a scrolling obstacle course (bots offline, real-time online).
Widget buildObstacleRaceGame(GameLaunch launch) => ObstacleGame(launch: launch);
