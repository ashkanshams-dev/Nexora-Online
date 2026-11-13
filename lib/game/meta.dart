// Progression meta — port of src/game/meta.ts: achievements, daily rewards, chests, daily deals.
import 'dart:math' as math;

import '../store.dart';
import 'assets.dart';
import 'data.dart';

class Ach {
  final String id, name, desc, icon;
  final int max, coins, gems;
  final int Function(Profile p) cur;
  const Ach(this.id, this.name, this.desc, this.icon, this.max, this.cur, this.coins, this.gems);
}

final List<Ach> ACHS = [
  Ach('first', 'اولین قدم', 'یک بازی انجام بده', 'x_ball', 1, (p) => p.played, 100, 0),
  Ach('win5', 'برنده', '۵ بازی ببر', 'x_medal', 5, (p) => p.wins, 250, 0),
  Ach('goals25', 'گلزن', '۲۵ گل بزن', 'x_statue', 25, (p) => p.goalsFor, 300, 0),
  Ach('streak3', 'شکست‌ناپذیر', '۳ برد پشت سر هم', 'x_star', 3, (p) => p.bestStreak, 350, 0),
  Ach('cup1', 'قهرمان', 'جام نکسورا را ببر', 'x_trophy', 1, (p) => p.cupsWon, 500, 0),
  Ach('collect', 'کلکسیونر', '۱۵ دیسک ویژه باز کن', 'x_team', 15, (p) => p.ownedTeams.where((id) => !id.startsWith('club') && !id.startsWith('nat') && !id.startsWith('iran')).length, 400, 0),
  Ach('win25', 'اسطوره', '۲۵ بازی ببر', 'x_crown', 25, (p) => p.wins, 800, 0),
  Ach('gold', 'لیگ طلا', 'به ۸۰۰ جام برس', 'x_shield', 800, (p) => p.trophies, 600, 0),
];

const DAILY = [(100, 0), (150, 0), (250, 0), (300, 0), (400, 0), (450, 0), (800, 0)];

enum ItemKind { team, ball, field }

class Item {
  final ItemKind kind;
  final Object id;
  final String name;
  final int price, rar;
  final String? img;
  const Item(this.kind, this.id, this.name, this.price, this.img, this.rar);
  Item withPrice(int p) => Item(kind, id, name, p, img, rar);
}

List<Item> allItems(Profile p) {
  final out = <Item>[];
  for (var i = 0; i < 36; i++) {
    if (ballPrice(i) > 0 && !p.ownedBalls.contains(i)) out.add(Item(ItemKind.ball, i, BALL_NAMES[i], ballPrice(i), BALL_IMG['b$i'], ballPrice(i) > 140 ? 2 : 1));
  }
  for (var i = 0; i < FIELDS.length; i++) {
    if (fieldPrice(i) > 0 && !p.ownedFields.contains(i)) out.add(Item(ItemKind.field, i, FIELDS[i].name, fieldPrice(i), FIELD_THUMB[FIELDS[i].id], fieldPrice(i) > 140 ? 2 : 1));
  }
  return out;
}

void grant(Item it, Profile q) {
  switch (it.kind) {
    case ItemKind.team:
      q.ownedTeams = [...q.ownedTeams, it.id as String];
    case ItemKind.ball:
      q.ownedBalls = [...q.ownedBalls, it.id as int];
    case ItemKind.field:
      q.ownedFields = [...q.ownedFields, it.id as int];
  }
}

/// deterministic per-day shuffle so "deals of the day" stay put until midnight (same xorshift as TS)
List<Item> dailyDeals(Profile p, [int n = 4]) {
  final items = allItems(p);
  final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
  var h = (day * 2654435761) & 0xFFFFFFFF;
  double rnd() {
    h = (h ^ (h << 13)) & 0xFFFFFFFF;
    h ^= h >> 17;
    h = (h ^ (h << 5)) & 0xFFFFFFFF;
    return (h % 10000) / 10000;
  }

  final a = [...items];
  for (var i = a.length - 1; i > 0; i--) {
    final j = (rnd() * (i + 1)).floor();
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a.take(n).map((it) => it.withPrice(((it.price * .7) / 5).round() * 5)).toList();
}

const int CHEST_EVERY = 4 * 3600 * 1000;

class ChestPrize {
  final Item? item;
  final int coins, gems;
  const ChestPrize(this.item, this.coins, this.gems);
}

final _r = math.Random();
ChestPrize rollChest(Profile p, bool premium) {
  final items = allItems(p).where((i) => premium ? i.rar >= 2 : true).toList();
  final r = _r.nextDouble();
  if (items.isNotEmpty && r < (premium ? .75 : .4)) {
    final w = items.map((i) => premium ? i.rar : 4 - i.rar).toList();
    var x = _r.nextDouble() * w.fold<int>(0, (a, b) => a + b);
    for (var i = 0; i < items.length; i++) {
      x -= w[i];
      if (x <= 0) return ChestPrize(items[i], premium ? 60 : 20, 0);
    }
  }
  return ChestPrize(null, premium ? 320 + (_r.nextDouble() * 200).round() : 80 + (_r.nextDouble() * 120).round(), 0);
}
