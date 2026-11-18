import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/kart_game.dart';

/// NEXORA Kart Racing (CTR style): 2-4 racers, drift mini-turbo, items, bots offline, real-time online.
Widget buildKartRacingGame(GameLaunch launch) => KartGame(launch: launch);
