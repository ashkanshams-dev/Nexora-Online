# NEXORA arcade — art drop-in contract

Every new game reads `assets/games/<id>/skin.json`. Put PNG/WebP files in that folder and list them under "sprites" (role → file name). Missing sprites fall back to the procedural renderer. "palette" (hex colours: bgTop, bgBottom, accent, accent2, glow, players[]) and "fx" (particles, glow, shake, trail, bloom multipliers) override the code defaults. Lobby icon: assets/arcade/pedestals/<id>.webp (falls back to the procedural medallion).

## kart_racing

- `kart_0` — kart seat 1, top-down, nose pointing RIGHT, ~2:1.4
- `kart_1` — kart seat 2
- `kart_2` — kart seat 3
- `kart_3` — kart seat 4
- `item_box` — item box (square)
- `oil` — oil slick (top-down)

## obstacle_race

- `runner_0` — runner seat 1, side view, facing camera/up
- `runner_1` — runner seat 2
- `runner_2` — runner seat 3
- `runner_3` — runner seat 4
- `sweeper` — rotating sweeper arm
- `block` — falling block

## bomb_arena

- `player_0` — bomber seat 1 (square, top-down)
- `player_1` — bomber seat 2
- `player_2` — bomber seat 3
- `player_3` — bomber seat 4
- `bomb` — bomb
- `crate` — destructible crate tile
- `wall` — solid wall tile
- `floor` — floor tile
- `pu_range` — power-up: range
- `pu_bomb` — power-up: +bomb
- `pu_speed` — power-up: speed

## pool8

- `_note` — uses the Billiards table skins (assets/ui/nx2/boards/billiards_*.webp) and ball art of the classic game

## mini_golf

- `ball` — golf ball (round)
- `hole` — cup/hole (round)
- `turf` — turf tile (seamless)
- `wall` — wall/bumper tile
- `flag` — flag

## basketball_battle

- `ball` — basketball (round)
- `hoop` — hoop + backboard (front view)
- `court` — court background (portrait)

## spy_mafia

- `card_back` — role card back (portrait)
- `spy` — spy role art
- `agent` — agent role art
- `loc_<n>` — location art per location index 0..11 (optional)

## stickman_arena

- `arena_bg` — arena background (landscape)
- `platform` — platform tile

## ludo_battle

- `_note` — uses the Ludo board art of the classic game; optional battle_bg for the frame

## chess_blitz

- `board` — board 8x8 (square)
- `wK` — white king
- `wQ` — white queen
- `wR` — white rook
- `wB` — white bishop
- `wN` — white knight
- `wP` — white pawn
- `bK` — black king
- `bQ` — black queen
- `bR` — black rook
- `bB` — black bishop
- `bN` — black knight
- `bP` — black pawn

## endless_runner

- `runner` — runner (side view, facing right)
- `obstacle` — ground obstacle
- `bird` — flying obstacle
- `coin` — coin
- `bg_far` — far parallax layer (landscape, seamless)
- `bg_near` — near parallax layer

## tetris_rush

- `block` — one mino cell (square, tinted per piece)

## helix_jump

- `ball` — ball
- `slab` — safe slab texture
- `danger` — danger slab texture

## fruit_ninja

- `fruit_0` — fruit 1 (round)
- `fruit_1` — fruit 2
- `fruit_2` — fruit 3
- `fruit_3` — fruit 4
- `fruit_4` — fruit 5
- `bomb` — bomb
- `wood_bg` — background

## geo_dash

- `player` — cube player (square)
- `spike` — spike
- `block` — block tile
- `bg` — background (seamless)

## traffic_racer

- `player_car` — player car (top-down, nose UP)
- `car_0` — traffic car 1
- `car_1` — traffic car 2
- `car_2` — traffic car 3
- `car_3` — traffic car 4
- `road` — road tile (seamless vertical)

## stack_tower

- `block` — block face texture (tinted)

## bubble_shooter

- `bubble_0` — bubble colour 1
- `bubble_1` — bubble colour 2
- `bubble_2` — bubble colour 3
- `bubble_3` — bubble colour 4
- `bubble_4` — bubble colour 5
- `bubble_5` — bubble colour 6

## knife_hit

- `knife` — knife (pointing UP)
- `log` — target log (round, top view)
- `apple` — apple

## game_2048

- `tile` — tile background (square, tinted per value)
