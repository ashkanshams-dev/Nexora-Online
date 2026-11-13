// Team / loadout — port of src/screens/Team.tsx: discs (hero + stats + buy/equip, categories incl. v11),
// balls, fields and formation pages.
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
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

const CAT_FA = {'club': 'باشگاه', 'iran': 'لیگ ایران', 'nat': 'ملی', 'elite': 'الیت', 'emb': 'ملی ویژه', 'leg': 'افسانه NX', 'vip': 'ملی NX', 'car': 'خودرو', 'lux': 'لوکس', 'spt': 'ورزشی'};
const CAT_ORDER = ['club', 'iran', 'nat', 'elite', 'emb', 'leg', 'vip', 'car', 'lux', 'spt'];

/// v10 categories in their RN order, then every v11 category (label from the catalogue)
List<(String, String)> discCats() => [
      for (final k in CAT_ORDER)
        if (CATS.any((c) => c.$1 == k)) (k, CAT_FA[k] ?? k),
      for (final c in CATS)
        if (!CAT_ORDER.contains(c.$1)) (c.$1, c.$2),
    ];

class TeamScreen extends StatefulWidget {
  final double top, bottom;
  final Toast toast;
  const TeamScreen({super.key, required this.top, required this.bottom, required this.toast});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  String sub = 'disc';
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: widget.top),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Segment<String>(value: sub, onChange: (v) => setState(() => sub = v), items: const [('disc', 'دیسک'), ('ball', 'توپ'), ('field', 'زمین'), ('form', 'ترکیب')]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: switch (sub) {
                'disc' => _Discs(key: const ValueKey('d'), bottom: widget.bottom, toast: widget.toast),
                'ball' => _Balls(key: const ValueKey('b'), bottom: widget.bottom, toast: widget.toast),
                'field' => _Fields(key: const ValueKey('f'), bottom: widget.bottom, toast: widget.toast),
                _ => _Formation(key: const ValueKey('o'), bottom: widget.bottom),
              },
            ),
          ),
        ]),
      );
}

class _Discs extends StatefulWidget {
  final double bottom;
  final Toast toast;
  const _Discs({super.key, required this.bottom, required this.toast});
  @override
  State<_Discs> createState() => _DiscsState();
}

class _DiscsState extends State<_Discs> {
  late String cat = teamById(Store.I.p.team).cat;
  late String focus = Store.I.p.team;
  bool busy = false;

  Future<void> act(Team ft, bool owned, int price) async {
    final dz = Discs.I, auth = Auth.I, st = Store.I;
    if (busy) return;
    if (owned) {
      st.set((q) => q.team = ft.id);
      buzz(Buzz.success);
      widget.toast('${ft.name} انتخاب شد', 'ok');
      if (auth.uid != null) dz.equip(ft.id).then((r) => r.ok ? null : widget.toast(r.error!, 'err'));
      return;
    }
    setState(() => busy = true);
    try {
      if (auth.uid == null && await auth.ensure() == null) return widget.toast('برای خرید باید آنلاین باشی', 'err');
      final g = ri(auth.profile, 'gems');
      if (auth.profile != null && g < price) {
        widget.toast('${fa(price - g)} الماس دیگر لازم داری · چالش‌های روزانه و تورنمنت‌ها الماس می‌دهند', 'err');
        return buzz(Buzz.medium);
      }
      final r = await dz.buy(ft.id);
      if (!r.ok) return widget.toast(r.error!, 'err');
      await dz.equip(ft.id);
      st.set((q) => q.team = ft.id);
      sfx(Sfx.win);
      buzz(Buzz.success);
      widget.toast('${ft.name} باز شد!', 'ok');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.sizeOf(context).width;
    final cell = (W - 32 - 3 * 8) / 4;
    return ListenableBuilder(
      listenable: Listenable.merge([Store.I, Discs.I, Auth.I]),
      builder: (context, _) {
        final p = Store.I.p, dz = Discs.I;
        final list = TEAMS.where((t) => t.cat == cat).toList();
        final ft = teamById(focus), owned = dz.has(ft.id);
        final price = dz.catalog[ft.id] != null ? ri(dz.catalog[ft.id], 'price_gems') : (isFreeDisc(ft.id) ? 0 : teamPrice(ft));
        final ds = discStats(ft.id), rr = RARITY[rarity(ft)];
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Column(children: [
              SizedBox(
                height: 170,
                child: Stack(alignment: Alignment.center, children: [
                  Pulse(size: 150, color: rr.c.withValues(alpha: .3)),
                  Img(UI2['ring'], w: 170, h: 170).animate(onPlay: (c) => c.repeat()).rotate(duration: 14.seconds),
                  Float(
                    amp: 5,
                    child: Container(
                      width: 128, height: 128, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: BG0, border: Border.all(color: rr.c, width: 3), boxShadow: glow(rr.c, 20, .7)),
                      child: ClipOval(child: Img(teamImg(teamKey(ft)), w: 122, h: 122)),
                    ).animate(key: ValueKey(ft.id)).scale(begin: const Offset(.7, .7), curve: Curves.elasticOut, duration: 700.ms),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: rr.c.withValues(alpha: .53)), color: rr.c.withValues(alpha: .11)),
                child: T(rr.n, style: fs(F.head, 9, ls: 3, color: rr.c)),
              ),
              Padding(padding: const EdgeInsets.only(top: 4), child: T(ft.name.toUpperCase(), n: 1, style: fs(F.title, 20, ls: 1))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Panel(
                  accent: rr.c,
                  pad: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    StatBars(power: ds.power.round(), accuracy: ds.accuracy.round()),
                    Padding(padding: const EdgeInsets.only(top: 6), child: T('قدرت = سرعت بیشینه‌ی ضربه · دقت = انحراف کمتر و پیش‌نمایش مسیر بلندتر', align: TextAlign.right, style: fs(F.body, 10, color: C.dim))),
                    const SizedBox(height: 10),
                    p.team == ft.id
                        ? Btn(label: 'انتخاب‌شده ✓', small: true, colors: G.dark, disabled: true)
                        : owned
                            ? Btn(label: 'انتخاب این دیسک', small: true, onPress: () => act(ft, owned, price))
                            : Btn(
                                label: busy ? '…' : 'خرید · 💎 ${fa(price)}',
                                sub: Auth.I.profile != null ? 'موجودی: ${fa(ri(Auth.I.profile, 'gems'))} الماس' : null,
                                small: true,
                                colors: G.violet,
                                disabled: busy,
                                onPress: () => act(ft, owned, price),
                              ),
                  ]),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.fromLTRB(8, 14, 8, 0), children: [
                  for (final (k, l) in discCats())
                    Chip2(label: l, on: cat == k, onPress: () => setState(() => cat = k), accent: k == 'leg' || k == 'vip' || k == 'carv' ? C.gold : k == 'emb' || k == 'flag' ? C.violet : C.cyan),
                ]),
              ),
              const SizedBox(height: 10),
            ]),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottom + 10),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: cell / (cell + 30)),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final t = list[i];
                  final own = dz.has(t.id), sel = t.id == focus, eq = t.id == p.team;
                  return Press(
                    onPress: () => setState(() => focus = t.id),
                    scaleTo: .93,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: sel ? C.cyan : C.line, width: sel ? 1.5 : 1),
                        color: sel ? rgba(79, 227, 255, .12) : rgba(10, 14, 40, .82),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Opacity(opacity: own ? 1 : .55, child: ClipOval(child: Img(teamImg(teamKey(t)), w: cell * .7, h: cell * .7))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: T(eq ? '✓ ${t.name}' : own ? t.name : '💎 ${fa(ri(dz.catalog[t.id], 'price_gems'))}', n: 1, style: fs(F.bold, 9, color: eq ? C.green : own ? C.text : C.violet)),
                        ),
                      ]),
                    ),
                  );
                },
                childCount: list.length,
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _Balls extends StatelessWidget {
  final double bottom;
  final Toast toast;
  const _Balls({super.key, required this.bottom, required this.toast});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.I,
        builder: (context, _) {
          final p = Store.I.p;
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .82),
            itemCount: 36,
            itemBuilder: (_, i) {
              final owned = p.ownedBalls.contains(i), price = ballPrice(i), sel = p.ball == i;
              return Press(
                onPress: () {
                  if (owned) {
                    Store.I.set((q) => q.ball = i);
                    buzz(Buzz.success);
                    return toast('توپ انتخاب شد', 'ok');
                  }
                  if (p.coins < price) return toast('سکه کافی نداری', 'err');
                  Store.I.set((q) {
                    q.coins -= price;
                    q.ownedBalls = [...q.ownedBalls, i];
                    q.ball = i;
                  });
                  sfx(Sfx.goal);
                  buzz(Buzz.success);
                  toast('توپ جدید باز شد!', 'ok');
                },
                child: Panel(
                  accent: sel ? C.cyan : null,
                  noAccent: !sel,
                  glow: sel,
                  pad: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Opacity(opacity: owned ? 1 : .6, child: ClipOval(child: Img(BALL_IMG['b$i'], w: 58, h: 58)).animate(onPlay: sel ? (c) => c.repeat() : null).rotate(duration: 6.seconds)),
                    Padding(padding: const EdgeInsets.only(top: 4), child: T(BALL_NAMES[i], n: 1, style: fs(F.bold, 11))),
                    T(sel ? '✓ فعال' : owned ? 'انتخاب' : '🪙 ${fa(price)}', style: fs(F.body, 10, color: sel ? C.green : owned ? C.dim : C.gold)),
                  ]),
                ),
              );
            },
          );
        },
      );
}

class _Fields extends StatelessWidget {
  final double bottom;
  final Toast toast;
  const _Fields({super.key, required this.bottom, required this.toast});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.I,
        builder: (context, _) {
          final p = Store.I.p;
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .62),
            itemCount: FIELDS.length,
            itemBuilder: (_, i) {
              final f = FIELDS[i], owned = p.ownedFields.contains(i), price = fieldPrice(i), sel = p.field == i;
              return Press(
                onPress: () {
                  if (owned) {
                    Store.I.set((q) => q.field = i);
                    buzz(Buzz.success);
                    return toast('زمین انتخاب شد', 'ok');
                  }
                  if (p.coins < price) return toast('سکه کافی نداری', 'err');
                  Store.I.set((q) {
                    q.coins -= price;
                    q.ownedFields = [...q.ownedFields, i];
                    q.field = i;
                  });
                  sfx(Sfx.goal);
                  buzz(Buzz.success);
                  toast('زمین جدید باز شد!', 'ok');
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? C.cyan : C.line, width: sel ? 2 : 1),
                    boxShadow: sel ? glow(C.cyan, 12, .6) : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    Opacity(opacity: owned ? 1 : .55, child: Img(FIELD_THUMB[f.id], fit: BoxFit.cover)),
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color: rgba(2, 4, 14, .75),
                        child: Column(children: [
                          T(f.name, n: 1, style: fs(F.bold, 10)),
                          T(sel ? '✓ فعال' : owned ? 'انتخاب' : '🪙 ${fa(price)}', style: fs(F.body, 9, color: sel ? C.green : owned ? C.dim : C.gold)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      );
}

class _Formation extends StatelessWidget {
  final double bottom;
  const _Formation({super.key, required this.bottom});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.I,
        builder: (context, _) {
          final p = Store.I.p, me = teamById(p.team);
          final sl = slots(p.form);
          return ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 10), children: [
            AspectRatio(
              aspectRatio: .75,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LayoutBuilder(builder: (_, bc) {
                  final w = bc.maxWidth, h = bc.maxHeight;
                  return Stack(children: [
                    Positioned.fill(child: Img(FIELD_THUMB[FIELDS[p.field].id], fit: BoxFit.cover)),
                    Positioned.fill(child: ColoredBox(color: rgba(2, 4, 14, .35))),
                    for (final (i, (x, y)) in sl.indexed)
                      AnimatedPositioned(
                        key: ValueKey('s$i'),
                        duration: Duration(milliseconds: 380 + i * 40),
                        curve: Curves.easeOutBack,
                        left: x * w - 24,
                        top: h - y * h * 1.9 - 24,
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 2), boxShadow: glow(C.cyan, 8, .6)),
                          child: ClipOval(child: Img(teamImg(teamKey(me)), w: 44, h: 44)),
                        ),
                      ),
                  ]);
                }),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, textDirection: TextDirection.rtl, children: [
              for (final (i, f) in FORMS.indexed)
                Press(
                  onPress: () => Store.I.set((q) => q.form = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: (MediaQuery.sizeOf(context).width - 48) / 3,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.form == i ? C.cyan : C.line),
                      color: p.form == i ? rgba(79, 227, 255, .15) : rgba(10, 14, 40, .82),
                    ),
                    child: Column(children: [T(f.$1, style: fs(F.title, 15)), T(f.$2, style: fs(F.body, 10, color: C.dim))]),
                  ),
                ),
            ]),
          ]);
        },
      );
}
