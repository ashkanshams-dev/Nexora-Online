// Ported from src/game/data.ts — auto-extracted NEXORA game data.
// ignore_for_file: constant_identifier_names
import 'dart:math' as math;

class Field { final String id, name, gs; final int W, H, L, R, T, B, cs, g;
  const Field(this.id, this.name, this.W, this.H, this.L, this.R, this.T, this.B, this.cs, this.g, this.gs); }

const Map<String, List<double>> GS = {
  'white': [840.0, 307.0, 0.0491, 0.9522],
  'wood': [840.0, 306.0, 0.0474, 0.9519],
  'ice': [840.0, 305.0, 0.0535, 0.9429],
  'black': [840.0, 235.0, 0.0521, 0.9527],
  'rope': [840.0, 246.0, 0.0493, 0.9528],
  'gold': [840.0, 237.0, 0.0431, 0.9521],
  'red': [840.0, 233.0, 0.0502, 0.9509],
  'blue': [840.0, 236.0, 0.0452, 0.9526],
};

int _jsRound(double v) { final f = v.floorToDouble(); return (v - f >= 0.5 ? f + 1 : f).toInt(); }
const double FS = 1.12;

const List<List<Object>> _RAW_FIELDS = [
  ['pitch', "NEXORA Pitch", 747, 1371, 27, 719, 90, 1279, 686, 123, 'white'],
  ['forest', "Forest", 1086, 1448, 195, 890, 127, 1311, 702, 130, 'wood'],
  ['ice', "Ice", 1086, 1448, 190, 895, 134, 1308, 700, 132, 'ice'],
  ['ocean', "Ocean", 1086, 1448, 191, 897, 108, 1313, 701, 132, 'blue'],
  ['street', "Street", 1086, 1448, 182, 902, 157, 1313, 706, 134, 'gold'],
  ['streetarena', "Street Arena", 1086, 1448, 194, 888, 117, 1309, 702, 130, 'rope'],
  ['lava', "Lava", 1086, 1448, 200, 884, 127, 1305, 699, 128, 'black'],
  ['stadium', "Stadium", 1086, 1448, 196, 888, 115, 1311, 701, 129, 'white'],
  ['checker', "Checker", 1086, 1448, 193, 890, 102, 1353, 704, 130, 'red'],
  ['futsal', "Futsal", 1086, 1448, 190, 895, 104, 1318, 697, 132, 'gold'],
  ['arena', "Arena", 1086, 1448, 199, 884, 118, 1313, 694, 128, 'red'],
  ['arena2', "Grand Arena", 1086, 1448, 164, 921, 135, 1302, 703, 134, 'gold'],
  ['desert', "Desert", 1086, 1448, 163, 920, 84, 1315, 694, 134, 'black'],
  ['grove', "Grove", 1086, 1448, 172, 918, 108, 1320, 695, 134, 'rope'],
  ['pool', "Pool", 1086, 1448, 160, 925, 98, 1312, 697, 134, 'white'],
  ['neon', "Neon Tech", 1024, 1536, 141, 883, 131, 1385, 745, 139, 'black'],
  ['royal', "Royal", 1024, 1536, 148, 877, 147, 1350, 730, 136, 'gold'],
  ['mahogany', "Mahogany", 1024, 1536, 97, 925, 90, 1393, 729, 155, 'wood'],
  ['leather', "Leather", 1024, 1536, 99, 925, 99, 1405, 730, 154, 'gold'],
  ['aqua', "Aquarium", 1024, 1536, 122, 905, 122, 1390, 742, 146, 'blue'],
  ['asphalt', "Asphalt", 1024, 1536, 97, 925, 113, 1417, 742, 155, 'rope'],
  ['court', "Court", 1024, 1536, 118, 907, 115, 1377, 715, 148, 'white'],
  ['cyberbox', "Cyber Box", 1024, 1536, 118, 906, 108, 1378, 706, 147, 'black'],
  ['realmadrid', "Real Madrid", 1086, 1448, 195, 889, 100, 1330, 722, 130, 'black'],
  ['psg', "Paris SG", 1086, 1448, 204, 881, 115, 1296, 666, 130, 'red'],
  ['acmilan', "AC Milan", 1086, 1448, 195, 889, 100, 1330, 722, 130, 'white'],
  ['barcelona', "FC Barcelona", 1086, 1448, 194, 889, 101, 1329, 721, 130, 'gold'],
  ['persepolis', "Persepolis", 1152, 1536, 207, 943, 135, 1410, 770, 130, 'white'],
  ['esteghlal', "Esteghlal", 1086, 1448, 195, 890, 100, 1322, 690, 130, 'gold'],
  ['mancity', "Man City", 1086, 1448, 195, 889, 102, 1329, 719, 130, 'red'],
];

final List<Field> FIELDS = _RAW_FIELDS.map((f) { int s(int i) => _jsRound((f[i] as int) * FS); return Field(f[0] as String, f[1] as String, s(2), s(3), s(4), s(5), s(6), s(7), s(8), _jsRound((f[9] as int) * 1.04), f[10] as String); }).toList(growable: false);

const List<(String, String, List<String>)> CATS = [
  ('club', 'Clubs', ["Barcelona", "Barcelona II", "Arsenal", "Liverpool", "Manchester United", "Celtic", "Ajax", "Inter Milan", "Inter Miami", "Wolfsburg", "Tottenham", "Aston Villa", "RB Leipzig", "Borussia Dortmund", "Lille", "Lyon", "Lille II", "Lyon II", "Lazio", "Napoli", "Al Hilal", "Monaco"]),
  ('nat', 'National', ["Argentina", "France", "Japan", "Portugal", "Spain", "England", "Brazil", "Italy", "Argentina II", "Germany", "Netherlands", "Belgium", "Mexico", "Portugal II", "Croatia", "Uruguay", "Senegal", "Morocco"]),
  ('lux', 'Luxury', ["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski", "Chanel II", "Louis Vuitton II", "Dior II", "Gucci II", "Saint Laurent II", "Prada II", "MAC", "Victoria's Secret", "Sephora", "Estee Lauder", "Lancome", "Zara", "H&M", "Uniqlo", "Pandora", "Kate Spade", "Coach", "Cartier II", "Tiffany & Co.", "PINK"]),
  ('car', 'Cars', ["Lamborghini", "Ferrari", "Rolls-Royce", "Mercedes-Benz", "BMW", "Porsche", "Maserati", "Aston Martin", "Bentley", "Bugatti", "Lexus", "Cadillac", "McLaren", "Tesla", "Lamborghini II", "Ferrari II", "Porsche II", "Mercedes-Benz II", "BMW II", "Aston Martin II", "Rolls-Royce II", "Bentley II", "Maserati II", "Bugatti II", "McLaren II", "Lexus II", "Tesla II", "Volvo", "Land Rover", "Audi", "Cadillac II", "Alfa Romeo", "Pagani", "Koenigsegg"]),
];

const List<(String, String, List<(double, int)>)> FORMS = [
  ('1-2-2', 'Balanced', [(0.09, 1), (0.22, 2), (0.36, 2)]),
  ('2-2-1', 'Cautious', [(0.1, 2), (0.24, 2), (0.37, 1)]),
  ('3-1-1', 'Wall', [(0.1, 3), (0.25, 1), (0.37, 1)]),
  ('2-1-2', 'Diamond', [(0.1, 2), (0.24, 1), (0.37, 2)]),
  ('1-3-1', 'Midfield', [(0.09, 1), (0.23, 3), (0.37, 1)]),
  ('1-1-3', 'Attack', [(0.09, 1), (0.22, 1), (0.36, 3)]),
];

class Trail { final String k; final List<String> c; const Trail(this.k, this.c); }
const List<Trail> TRAILS = [
  Trail('bolt', ['#19b4ff','#8fe6ff','#ffffff']),
  Trail('prism', ['#ff7bd5','#7bd7ff','#ffffff']),
  Trail('wave', ['#2fe0d0','#9ff7ef','#ffffff']),
  Trail('star', ['#5cb6ff','#bfe3ff','#ffffff']),
  Trail('smoke', ['#e8ecf2','#9aa3b0','#ffffff']),
  Trail('rainbow', ['#ff5b5b','#ffd23a','#5bff8a','#5bd0ff','#c05bff']),
  Trail('neon', ['#4dff2a','#b6ff9a','#ffffff']),
  Trail('yin', ['#ffffff','#9b5cff','#000000']),
  Trail('fire', ['#ff8a1f','#ffd24a','#fff3c4']),
  Trail('blade', ['#ff2b3a','#ff8a92','#ffffff']),
  Trail('ghost', ['#dbe7ff','#8fb0ff','#ffffff']),
  Trail('ember', ['#ff6a1f','#ffb347','#fff0c8']),
  Trail('plasma', ['#2f8bff','#7fc6ff','#ffffff']),
  Trail('ghost', ['#d9915b','#f2c9a0','#fff4e6']),
  Trail('star', ['#2f7bff','#8fd0ff','#ffffff']),
  Trail('wave', ['#9b5cff','#e0b8ff','#ffffff']),
  Trail('fire', ['#e0a82e','#ffe08a','#fff7d6']),
  Trail('bolt', ['#2f6bff','#7fb4ff','#ffffff']),
  Trail('neon', ['#2f8bff','#e8b84a','#ffffff']),
  Trail('prism', ['#1fd6a0','#3b9bff','#ffffff']),
  Trail('blade', ['#ff2b3a','#ff8a92','#ffffff']),
  Trail('plasma', ['#18d8c0','#9ff5e6','#ffffff']),
  Trail('ember', ['#2f5bff','#ffc83a','#fff3c4']),
  Trail('yin', ['#ffffff','#e0a82e','#000000']),
  Trail('smoke', ['#ff4a4a','#9aa3b0','#ffffff']),
  Trail('star', ['#e0a82e','#fff0b0','#ffffff']),
  Trail('plasma', ['#2f8bff','#c0c8d8','#ffffff']),
  Trail('ghost', ['#9b5cff','#ffffff','#ffffff']),
  Trail('neon', ['#4dff2a','#c0c8d8','#ffffff']),
  Trail('blade', ['#e8b84a','#2f6bff','#ffffff']),
  Trail('fire', ['#ff2b3a','#ff8a92','#ffffff']),
  Trail('ember', ['#ff8a1f','#ffd24a','#ffffff']),
  Trail('wave', ['#3b9bff','#2fe08a','#ffffff']),
  Trail('prism', ['#ff4a7a','#9b5cff','#ffffff']),
  Trail('bolt', ['#2f6bff','#ffffff','#ffffff']),
  Trail('star', ['#ffd56b','#ffffff','#ffffff']),
];

const List<String> BALL_NAMES = ['Bolt','Prism','Wave','Starlight','Classic','Rainbow','Neon','Yin','Fire','Blade','Ghost','Ember','Plasma','Noir Copper','Space Modern','Purple Sky','Black Lux','Electron','Cobalt Gold','Aurora','Crimson','Teal Storm','Royal Gold','Gold Rush','Classic Red','Luxury','Noir Chrome','Violet Strike','Emerald Edge','Royal Blue Gold','Crimson Noir','Blaze Orange','Aqua Wave','Sunset Pro','Elite Cobalt','Crown Luxury'];

class FieldFx { final int k; final List<String> c; final int g; const FieldFx(this.k, this.c, this.g); }
const Map<String, FieldFx> FIELD_FX = {
  'pitch': FieldFx(1, ['#ffffff','#d8ffb0','#7bff5a'], 0),
  'forest': FieldFx(2, ['#6fd36b','#b8f5a0','#2e8b3a'], 130),
  'ice': FieldFx(1, ['#e8fbff','#9fe8ff','#ffffff'], 30),
  'ocean': FieldFx(4, ['#bff3ff','#5cd0ff','#ffffff'], -140),
  'street': FieldFx(5, ['#ff2bd6','#ffe14a','#2bf0ff'], 0),
  'streetarena': FieldFx(5, ['#ffb02b','#ff3b6b','#ffffff'], 0),
  'lava': FieldFx(0, ['#ff5a1f','#ffb347','#ffe08a'], -220),
  'stadium': FieldFx(1, ['#ffd86b','#ffffff','#ffe9a8'], 0),
  'checker': FieldFx(3, ['#ffffff','#9aa3b0','#ff4040'], 0),
  'futsal': FieldFx(5, ['#ffcf8a','#ffffff','#ffa14a'], 0),
  'arena': FieldFx(5, ['#7fb8ff','#ffffff','#3b7bff'], 0),
  'arena2': FieldFx(1, ['#c79bff','#ffffff','#7b4bff'], 0),
  'desert': FieldFx(0, ['#e8c689','#c99a54','#fff0c8'], 60),
  'grove': FieldFx(0, ['#d8ff6a','#ffffa0','#9cf06a'], -30),
  'pool': FieldFx(0, ['#9fe9ff','#e6fbff','#4cc7ff'], 380),
  'neon': FieldFx(5, ['#7dff3a','#d6ff9a','#ffffff'], 0),
  'royal': FieldFx(1, ['#ffd86b','#fff3c4','#ff9a3a'], 0),
  'mahogany': FieldFx(1, ['#ffcf8a','#fff0c8','#d9923a'], -20),
  'leather': FieldFx(0, ['#d9a066','#ffd9a0','#8a5a2a'], -30),
  'aqua': FieldFx(4, ['#bff3ff','#5cd0ff','#ffffff'], -150),
  'asphalt': FieldFx(5, ['#ffe14a','#ffffff','#ffb02b'], 0),
  'court': FieldFx(5, ['#ffffff','#ffcf8a','#4aa8ff'], 0),
  'cyberbox': FieldFx(5, ['#ff3b3b','#3b8bff','#ffffff'], 0),
  'realmadrid': FieldFx(1, ['#ffffff','#ffd86b','#3b6bff'], 0),
  'psg': FieldFx(5, ['#ff2b3a','#3b6bff','#ffffff'], 0),
  'acmilan': FieldFx(5, ['#ff2b3a','#ffffff','#111111'], 0),
  'barcelona': FieldFx(5, ['#ff2b5a','#3b6bff','#ffd86b'], 0),
  'persepolis': FieldFx(5, ['#ff2b3a','#ffd86b','#ffffff'], 0),
  'esteghlal': FieldFx(1, ['#3b8bff','#ffffff','#ffd86b'], 0),
  'mancity': FieldFx(1, ['#7fd0ff','#ffffff','#3b8bff'], 0),
};

class Team { final String id, cat, name; final int idx; const Team(this.id, this.cat, this.name, this.idx); }
final List<Team> TEAMS = [for (final c in CATS) for (var i = 0; i < c.$3.length; i++) Team('${c.$1}$i', c.$1, c.$3[i], i)];
final Map<String, String> CAT_LABEL = {for (final c in CATS) c.$1: c.$2};
int teamPrice(Team t) => t.cat == 'club' || t.cat == 'nat' ? 0 : 130;
int ballPrice(int i) => i < 6 ? 0 : 60 + (i % 7) * 20;
/// index 0 is the free default NEXORA Pitch
int fieldPrice(int i) => i < 5 ? 0 : 80 + ((i - 1) % 5) * 20;
const int DEFAULT_FIELD = 0;
const int FIELDS_VERSION = 2;
List<(double, double)> slots(int fi) {
  final o = <(double, double)>[];
  for (final (ny, c) in FORMS[fi].$3) {
    for (var i = 0; i < c; i++) {
      o.add((c == 1 ? .5 : c == 2 ? .27 + .46 * i : .17 + .33 * i, ny));
    }
  }
  return o;
}
// keep dart:math referenced for consumers
final double kTau = math.pi * 2;
