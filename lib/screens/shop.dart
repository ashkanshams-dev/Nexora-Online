// Shop — port of src/screens/Shop.tsx: legendary disc banner + rail (gems), supply chests, daily deals, catalogue.
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/meta.dart';
import '../game/util.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../sound.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

typedef Toast = void Function(String m, [String k]);
final _RC = [hex('#8ea3d6'), hex('#4fe3ff'), hex('#b46bff'), hex('#ffd257')];

Widget priceTag(int v, {bool gem = false}) => Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
      Img(gem ? UI2['x_gem'] : UI2['c_coin'], w: 16, h: 16),
      Padding(padding: const EdgeInsets.only(right: 3), child: Text(fa(v), style: fs(F.head, 11, color: gem ? hex('#9fd8ff') : C.gold))),
    ]);

String _fmt(int ms) {
  final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
  return '${fa(h)}:${faNum(m.toString().padLeft(2, '0'))}';
}

class Shop extends StatefulWidget {
  final double top, bottom;
  final Toast toast;
  final void Function(bool premium) onChest;
  const Shop({super.key, required this.top, required this.bottom, required this.toast, required this.onChest});
  @override
  State<Shop> createState() => _ShopState();
}

class _ShopState extends State<Shop> {
  ItemKind kind = ItemKind.ball;

  void buy(Item it) {
    final p = Store.I.p;
    if (p.coins < it.price) {
      widget.toast('سکه کافی نداری', 'err');
      return buzz(Buzz.medium);
    }
    Store.I.set((q) {
      q.coins -= it.price;
      grant(it, q);
    });
    sfx(Sfx.goal);
    buzz(Buzz.success);
    widget.toast('${it.name} باز شد!', 'ok');
  }

  Future<void> buyDisc(String id, String name) async {
    if (await Discs.I.buyAndEquip(id, name, widget.toast)) {
      Store.I.set((q) => q.team = id);
      sfx(Sfx.win);
      buzz(Buzz.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: Listenable.merge([Store.I, Discs.I, Auth.I]),
      builder: (context, _) {
        final p = Store.I.p, dz = Discs.I;
        final deals = dailyDeals(p), items = allItems(p).where((i) => i.kind == kind).toList();
        final legends = TEAMS.where((t) => t.cat == 'lux' || t.cat == 'car' || t.cat == 'carv').toList();
        final now = DateTime.now().millisecondsSinceEpoch, freeIn = (p.lastChest + CHEST_EVERY - now).clamp(0, CHEST_EVERY);
        final gemDiscs = dz.catalog.values.where((d) => ri(d, 'price_gems') > 0 && !dz.owned.contains(d['id'])).toList()..sort((a, b) => ri(a, 'price_gems').compareTo(ri(b, 'price_gems')));
        final cell = (W - 32 - 16) / 3;
        final hero = legends.isEmpty ? null : legends[(now ~/ 86400000) % legends.length];
        return ListView(padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom + 10), children: [
          Enter(
            i: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: rgba(255, 210, 87, .45)),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hex('#3b1a00'), hex('#1a0d3a'), hex('#070a22')]),
                  boxShadow: glow(C.gold, 16, .35),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  Positioned(right: -30, top: -10, child: Opacity(opacity: .25, child: Img(UI2['screens'], w: 260, h: 180))),
                  Row(children: [
                    if (hero != null) Padding(padding: const EdgeInsets.all(10), child: Float(amp: 6, child: Img(teamImg(teamKey(hero)), w: 110, h: 110))),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                          T('LEGENDARY DISCS', style: fs(F.head, 9, ls: 3, color: C.gold)),
                          T('دیسک‌های افسانه‌ای', style: fs(F.title, 19)),
                          T('قدرت و دقت بالا · با الماس', style: fs(F.body, 11, color: hex('#e8d7ad'))),
                          Container(
                            margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: C.gold),
                            child: T('محدود', style: fs(F.bold, 11, color: hex('#1b0e00'))),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ).animate().shimmer(delay: 600.ms, duration: 1800.ms, color: const Color(0x33FFE08A)),
            ),
          ),
          SizedBox(
            height: 170,
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), children: [
              for (final (i, t) in legends.indexed)
                Enter(
                  i: i,
                  child: Press(
                    onPress: () => dz.has(t.id) ? null : buyDisc(t.id, t.name),
                    child: Opacity(
                      opacity: dz.has(t.id) ? .6 : 1,
                      child: Container(
                        width: 118, margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: rgba(255, 210, 87, .35)),
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(255, 210, 87, .25), rgba(10, 12, 34, .9)]),
                        ),
                        child: Column(children: [
                          Img(teamImg(teamKey(t)), w: 92, h: 92),
                          Padding(padding: const EdgeInsets.only(top: 4), child: T(t.name, n: 1, style: fs(F.bold, 11))),
                          dz.has(t.id) ? T('✓ داری', style: fs(F.body, 11, color: C.green)) : priceTag(ri(dz.catalog[t.id], 'price_gems'), gem: true),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Title2('صندوقچه‌ها', en: 'SUPPLY CHESTS', accent: C.violet),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(textDirection: TextDirection.rtl, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Panel(
                    accent: C.cyan,
                    glow: freeIn == 0,
                    pad: const EdgeInsets.all(12),
                    child: Column(children: [
                      _shake(Img(UI2['c_chest'], w: 96, h: 96), freeIn == 0),
                      T('صندوقچه‌ی رایگان', style: fs(F.bold, 13)),
                      T('هر ۴ ساعت', style: fs(F.body, 10, color: C.dim)),
                      const SizedBox(height: 8),
                      Btn(small: true, label: freeIn > 0 ? _fmt(freeIn) : 'باز کن', disabled: freeIn > 0, onPress: () => widget.onChest(false)),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Panel(
                    accent: C.gold,
                    glow: true,
                    pad: const EdgeInsets.all(12),
                    child: Column(children: [
                      _shake(Img(UI2['x_chest'], w: 96, h: 96), true),
                      T('صندوقچه‌ی سلطنتی', style: fs(F.bold, 13)),
                      T('آیتم کمیاب تضمینی‌تر', style: fs(F.body, 10, color: C.dim)),
                      const SizedBox(height: 8),
                      Btn(small: true, label: '۶۰۰ سکه', icon: UI2['c_coin'], colors: G.violet, onPress: () => p.coins < 600 ? widget.toast('۶۰۰ سکه لازمه', 'err') : widget.onChest(true)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          if (deals.isNotEmpty) Title2('پیشنهاد امروز', en: 'DAILY DEALS · -30%', accent: C.green),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, textDirection: TextDirection.rtl, children: [
              for (final (i, it) in deals.indexed)
                SizedBox(
                  width: (W - 32 - 8) / 2,
                  child: Enter(
                    i: i,
                    child: Press(
                      onPress: () => buy(it),
                      child: Panel(
                        accent: _RC[it.rar],
                        pad: const EdgeInsets.all(10),
                        child: Row(textDirection: TextDirection.rtl, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(it.kind == ItemKind.field ? 6 : 27), child: Img(it.img, w: it.kind == ItemKind.field ? 40 : 54, h: 54, fit: it.kind == ItemKind.field ? BoxFit.cover : BoxFit.contain)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                T(it.name, n: 1, style: fs(F.bold, 12)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6), margin: const EdgeInsets.symmetric(vertical: 2),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: C.green),
                                  child: T('-۳۰٪', style: fs(F.bold, 10, color: hex('#03140c'))),
                                ),
                                priceTag(it.price),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const Title2('همه‌ی تجهیزات', en: 'CATALOGUE'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Segment<ItemKind>(value: kind, accent: C.gold, onChange: (v) => setState(() => kind = v), items: const [(ItemKind.team, 'دیسک'), (ItemKind.ball, 'توپ'), (ItemKind.field, 'زمین')]),
          ),
          if (kind == ItemKind.team && Auth.I.profile == null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: T('قیمت دیسک‌ها به الماس است؛ با ورود آنلاین (حتی مهمان) ۱۵۰ الماس هدیه می‌گیری.', align: TextAlign.right, style: fs(F.body, 11, color: C.dim))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, textDirection: TextDirection.rtl, children: [
              if (kind == ItemKind.team)
                for (final d in gemDiscs.take(60))
                  SizedBox(
                    width: cell,
                    child: Press(
                      onPress: () => buyDisc(d['id'] as String, d['name'] as String),
                      scaleTo: .93,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _RC[ri(d, 'price_gems') >= 250 ? 3 : ri(d, 'price_gems') >= 180 ? 2 : 1].withValues(alpha: .4)), color: rgba(10, 14, 40, .82)),
                        child: Column(children: [
                          ClipOval(child: Img(discImgOf(d['id'] as String), w: cell * .6, h: cell * .6)),
                          Padding(padding: const EdgeInsets.only(top: 4), child: T(d['name'] as String, n: 1, style: fs(F.bold, 10))),
                          StatBars(power: ri(d, 'power'), accuracy: ri(d, 'accuracy'), compact: true),
                          priceTag(ri(d, 'price_gems'), gem: true),
                        ]),
                      ),
                    ),
                  )
              else
                for (final it in items.take(60))
                  SizedBox(
                    width: cell,
                    child: Press(
                      onPress: () => buy(it),
                      scaleTo: .93,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _RC[it.rar].withValues(alpha: .4)), color: rgba(10, 14, 40, .82)),
                        child: Column(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(it.kind == ItemKind.field ? 6 : cell), child: Img(it.img, w: it.kind == ItemKind.field ? cell * .5 : cell * .6, h: cell * .66, fit: it.kind == ItemKind.field ? BoxFit.cover : BoxFit.contain)),
                          Padding(padding: const EdgeInsets.only(top: 4), child: T(it.name, n: 1, style: fs(F.bold, 10))),
                          priceTag(it.price),
                        ]),
                      ),
                    ),
                  ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _shake(Widget w, bool on) => on
      ? w.animate(onPlay: (c) => c.repeat()).shake(hz: 3, rotation: .05, duration: 600.ms).then(delay: 1400.ms)
      : w;
}

/// chest opening card (modal)
class ChestOpen extends StatelessWidget {
  final ChestPrize prize;
  final bool premium;
  final VoidCallback onDone;
  const ChestOpen({super.key, required this.prize, required this.premium, required this.onDone});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 150,
            child: Stack(alignment: Alignment.center, children: [
              Opacity(opacity: .5, child: Img(UI2['ring'], w: 150, h: 150)).animate(onPlay: (c) => c.repeat()).rotate(duration: 8.seconds),
              Img(prize.item?.img ?? UI2[premium ? 'x_chest' : 'c_chest'], w: 110, h: 110).animate().scale(begin: const Offset(.2, .2), curve: Curves.elasticOut, duration: 900.ms),
            ]),
          ),
          T(prize.item != null ? prize.item!.name : 'صندوقچه باز شد!', style: fs(F.title, 20)),
          Padding(padding: const EdgeInsets.only(top: 6), child: T('+${fa(prize.coins)} سکه', style: fs(F.bold, 14, color: C.gold))),
          const SizedBox(height: 16),
          Btn(label: 'عالی!', colors: premium ? G.gold : G.primary, onPress: onDone),
        ]),
      );
}
