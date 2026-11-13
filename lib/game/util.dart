// Port of src/game/util.ts
import 'package:material_ui/material_ui.dart' show Color;

import 'data.dart';
import 'engine.dart' show imul32, u32;

String teamKey(Team t) => t.cat + t.idx.toString().padLeft(2, '0');
Team teamById(String id) => TEAMS.firstWhere((t) => t.id == id, orElse: () => TEAMS[0]);

/// FNV-1a over UTF-16 code units, identical to the TS `hash`
int hash(String s) {
  var h = 2166136261;
  for (final cu in s.codeUnits) {
    h = u32(h ^ cu);
    h = imul32(h, 16777619);
  }
  return u32(h);
}

class CardStats {
  final int power, control, speed, spin;
  const CardStats(this.power, this.control, this.speed, this.spin);
}

/// cosmetic card stats (do not affect physics). JS `>>` works on signed int32, reproduce that.
CardStats cardStats(String seed) {
  final h = hash(seed);
  final s = h >= 0x80000000 ? h - 0x100000000 : h;
  int jsMod(int a, int n) => a.remainder(n); // JS % keeps the dividend's sign
  return CardStats(60 + (h % 37), 55 + jsMod(s >> 6, 42), 58 + jsMod(s >> 12, 40), 50 + jsMod(s >> 18, 46));
}

int rarity(Team t) => (t.cat == 'vip' || t.cat == 'leg')
    ? 3
    : (t.cat == 'lux' || t.cat == 'car' || t.cat == 'emb')
        ? 2
        : (t.cat == 'spt' || t.cat == 'elite')
            ? 1
            : 0;

class Rarity {
  final String n;
  final Color c;
  const Rarity(this.n, this.c);
}

const List<Rarity> RARITY = [
  Rarity('COMMON', Color(0xFF8EA3D6)),
  Rarity('RARE', Color(0xFF4FE3FF)),
  Rarity('EPIC', Color(0xFFB46BFF)),
  Rarity('LEGENDARY', Color(0xFFFFD257)),
];
