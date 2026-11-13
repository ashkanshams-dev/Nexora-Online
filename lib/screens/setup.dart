// Match setup sheet + launch builder — port of src/screens/Setup.tsx.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../game/util.dart';
import '../net/discs.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

enum ModeKey { quick, local, cup, galaxy, train }

class Mode {
  final ModeKey k;
  final String img, name, en, desc, reward;
  final Color Function() color;
  const Mode(this.k, this.img, this.name, this.en, this.desc, this.reward, this.color);
}

final List<Mode> MODES = [
  Mode(ModeKey.quick, UI['portal_gamepad']!, 'بازی سریع', 'QUICK MATCH', 'یک مسابقه‌ی فوری مقابل هوش مصنوعی', 'سکه، XP و جام', () => C.cyan),
  Mode(ModeKey.cup, UI['portal_globe']!, 'جام نکسورا', 'NEXORA CUP', 'سه حریف پشت سر هم تا فینال؛ هر مرحله سخت‌تر', '۲ برابر جایزه + ۲۰ الماس قهرمانی', () => C.gold),
  Mode(ModeKey.galaxy, UI['portal_galaxy']!, 'چالش کهکشانی', 'GALAXY CHALLENGE', 'دو دقیقه مقابل ربات افسانه‌ای', '۳ برابر جایزه', () => C.violet),
  Mode(ModeKey.local, UI['portal_friends']!, 'دو نفره', 'LOCAL 2 PLAYER', 'با دوستت روی یک گوشی بازی کن', 'فقط برای افتخار', () => C.green),
  Mode(ModeKey.train, UI['portal_brain']!, 'تمرین', 'TRAINING', 'بدون تایمر، ربات آسان، برای گرم کردن دست', 'XP کم، بدون جام', () => C.sky),
];

class Launch {
  final MatchCfg cfg;
  final List<Team> teams;
  final List<String> names;
  final ModeKey mode;
  final int stage;
  const Launch(this.cfg, this.teams, this.names, this.mode, [this.stage = 0]);
}

final _rnd = math.Random();
List<Team> _pool() => TEAMS.where((t) => t.cat == 'club' || t.cat == 'nat' || t.cat == 'elite').toList();
Team pickOpp() {
  final p = _pool();
  return p[_rnd.nextInt(p.length)];
}

bool _boosted(Team t) => t.cat == 'vip' || t.cat == 'leg';

Launch buildLaunch(ModeKey mode, Profile p, {required int lvl, required String rule, required int tt, required Team opp, int stage = 0}) {
  final me = teamById(p.team), oppForm = _rnd.nextInt(FORMS.length);
  final ai = mode != ModeKey.local;
  var l = lvl, limit = rule == 'g5' ? 5 : 3;
  double matchTime = rule == 't3' ? 180 : 0;
  var t = tt;
  if (mode == ModeKey.cup) {
    l = math.min(2, stage);
    limit = 3;
    matchTime = 0;
  }
  if (mode == ModeKey.galaxy) {
    l = 2;
    matchTime = 120;
    limit = 99;
  }
  if (mode == ModeKey.train) {
    l = 0;
    t = 0;
  }
  final cfg = MatchCfg(
    field: p.field, ball: p.ball, forms: [p.form, ai ? oppForm : p.form], ai: ai, aiLvl: l, limit: limit,
    matchTime: matchTime, turnTime: t.toDouble(), vip: [_boosted(me), _boosted(opp)], first: 0,
    stats: [discStats(me.id), discStats(opp.id)],
  );
  return Launch(cfg, [me, opp], [p.name, ai ? opp.name : 'بازیکن ۲'], mode, stage);
}

class Setup extends StatefulWidget {
  final Mode mode;
  final void Function(Launch l) onStart;
  final VoidCallback onTeam;
  const Setup({super.key, required this.mode, required this.onStart, required this.onTeam});
  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  late int lvl = Store.I.p.aiLvl;
  late String rule = Store.I.p.limit == 5 ? 'g5' : 'g3';
  late int tt = Store.I.p.turnTime;
  Team opp = pickOpp();

  Widget _row(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 6), child: T(label, align: TextAlign.right, style: fs(F.bold, 13, color: C.dim))),
          child,
        ]),
      );

  Widget _disc(String? img, Color c) => Container(
        width: 72, height: 72, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 3), color: hex('#050816'), boxShadow: [BoxShadow(color: c.withValues(alpha: .8), blurRadius: 12)]),
        child: ClipOval(child: Img(img, w: 64, h: 64)),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.mode, mc = m.color();
    return ListenableBuilder(
      listenable: Store.I,
      builder: (context, _) {
        final p = Store.I.p, me = teamById(p.team);
        final local = m.k == ModeKey.local;
        final showLvl = m.k == ModeKey.quick, showRule = m.k == ModeKey.quick || local, showTT = m.k != ModeKey.train;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
          SizedBox(
            height: 150,
            child: Stack(alignment: Alignment.center, children: [Pulse(size: 120, color: mc.withValues(alpha: .33)), Float(amp: 5, child: Img(m.img, w: 140, h: 150))]),
          ),
          T(m.desc, align: TextAlign.center, style: fs(F.body, 14, color: hex('#c8e2ff'))),
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: mc.withValues(alpha: .4)), color: mc.withValues(alpha: .09)),
              child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
                Padding(padding: const EdgeInsets.only(left: 6), child: Img(UI2['c_coin'], w: 22, h: 22)),
                T(m.reward, style: fs(F.body, 12, color: hex('#ffe9a8'))),
              ]),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.line),
              gradient: LinearGradient(colors: [rgba(79, 227, 255, .18), rgba(10, 18, 48, .85), rgba(255, 74, 90, .18)]),
            ),
            child: Row(children: [
              Expanded(
                child: Press(
                  onPress: widget.onTeam,
                  child: Column(children: [
                    _disc(teamImg(teamKey(me)), C.cyan),
                    Padding(padding: const EdgeInsets.only(top: 6), child: T(me.name, n: 1, style: fs(F.bold, 12))),
                    T('تغییر تیم', style: fs(F.body, 10, color: C.cyan)),
                  ]),
                ),
              ),
              Img(UI['vs'], w: 70, h: 60),
              Expanded(
                child: Press(
                  onPress: () => !local ? setState(() => opp = pickOpp()) : null,
                  child: Column(children: [
                    _disc(teamImg(teamKey(local ? me : opp)), C.red),
                    Padding(padding: const EdgeInsets.only(top: 6), child: T(local ? 'بازیکن ۲' : opp.name, n: 1, style: fs(F.bold, 12))),
                    T(local ? ' ' : 'حریف دیگر ↻', style: fs(F.body, 10, color: C.red)),
                  ]),
                ),
              ),
            ]),
          ),
          if (m.k == ModeKey.cup)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: rgba(255, 210, 87, .07), border: Border.all(color: rgba(255, 210, 87, .25))),
              child: Row(textDirection: TextDirection.rtl, children: [
                for (final (i, n) in const ['یک‌چهارم', 'نیمه‌نهایی', 'فینال'].indexed)
                  Expanded(
                    child: Column(children: [
                      Opacity(opacity: i == 0 ? 1 : .55, child: Img(i == 2 ? UI2['x_trophy'] : UI2['x_medal'], w: 46, h: 46)),
                      T(n, style: fs(F.body, 11, color: i == 0 ? C.gold : C.dim)),
                      T(const ['آسان', 'معمولی', 'سخت'][i], style: fs(F.body, 10, color: C.dim2)),
                    ]),
                  ),
              ]),
            ),
          if (showLvl) _row('سختی', Segment<int>(value: lvl, onChange: (v) => setState(() => lvl = v), items: const [(0, 'آسان'), (1, 'معمولی'), (2, 'سخت')])),
          if (showRule) _row('قانون', Segment<String>(value: rule, onChange: (v) => setState(() => rule = v), accent: C.violet, items: const [('g3', 'تا ۳ گل'), ('g5', 'تا ۵ گل'), ('t3', '۳ دقیقه')])),
          if (showTT) _row('زمان نوبت', Segment<int>(value: tt, onChange: (v) => setState(() => tt = v), accent: C.green, items: const [(0, 'خاموش'), (10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث')])),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Press(
              onPress: widget.onTeam,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: rgba(10, 18, 48, .85), border: Border.all(color: C.line)),
                child: Row(children: [
                  ClipOval(child: Img(BALL_IMG['b${p.ball}'], w: 38, h: 38)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        T('${BALL_NAMES[p.ball]} · ${FIELDS[p.field].name}', n: 1, style: fs(F.bold, 12)),
                        T('ترکیب ${FORMS[p.form].$1} · تجهیزات', style: fs(F.body, 11, color: C.dim)),
                      ]),
                    ),
                  ),
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: Img(FIELD_THUMB[FIELDS[p.field].id], w: 30, h: 40, fit: BoxFit.cover)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Btn(
            label: m.k == ModeKey.cup ? 'شروع جام' : 'شروع بازی',
            colors: m.k == ModeKey.cup ? G.gold : G.primary,
            onPress: () {
              Store.I.set((q) {
                q.aiLvl = lvl;
                q.limit = rule == 'g5' ? 5 : 3;
                q.turnTime = tt;
              });
              widget.onStart(buildLaunch(m.k, Store.I.p, lvl: lvl, rule: rule, tt: tt, opp: opp));
            },
          ),
        ]);
      },
    );
  }
}
