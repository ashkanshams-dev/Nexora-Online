import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/basket_game.dart';

/// NEXORA Basketball Battle: 60-second shoot-out, 2-4 players, bots offline, live scores online.
Widget buildBasketballBattleGame(GameLaunch launch) => BasketGame(launch: launch);
