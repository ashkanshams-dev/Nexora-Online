// Profile — port of src/screens/Profile.tsx (offline career card + stats + achievements; online card on top).
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/meta.dart';
import '../game/util.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../sound.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

typedef Toast = void Function(String m, [String k]);

class ProfileScreen extends StatefulWidget {
  final double top, bottom;
  final Toast toast;
  const ProfileScreen({super.key, required this.top, required this.bottom, required this.toast});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(text: Store.I.p.name);

  void claim(Ach a) {
    final p = Store.I.p;
    if (p.claimedAch.contains(a.id)) return;
    Store.I.set((q) {
      q.claimedAch = [...q.claimedAch, a.id];
      q.coins += a.coins;
      q.gems += a.gems;
    });
    sfx(Sfx.goal);
    buzz(Buzz.success);
    widget.toast('+${fa(a.coins)} سکه · +${fa(a.gems)} الماس', 'ok');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Store.I, Auth.I]),
        builder: (context, _) {
          final p = Store.I.p, lv = level(p.xp), lg = league(p.trophies), t = teamById(p.team), prof = Auth.I.profile;
          final stats = [
            (UI2['x_ball'], 'بازی', p.played), (UI2['x_medal'], 'برد', p.wins), (UI2['x_shield'], 'باخت', p.losses),
            (UI2['x_star'], 'مساوی', p.draws), (UI2['x_statue'], 'گل زده', p.goalsFor), (UI2['x_trophy'], 'جام قهرمانی', p.cupsWon),
          ];
          return ListView(padding: EdgeInsets.fromLTRB(16, widget.top, 16, widget.bottom + 10), children: [
            if (prof != null)
              Enter(
                i: 0,
                child: Panel(
                  accent: C.cyan,
                  glow: true,
                  pad: const EdgeInsets.all(14),
                  child: Row(textDirection: TextDirection.rtl, children: [
                    AvatarO(avatar: prof['equipped_disc'] as String?, url: prof['avatar_url'] as String?, size: 64),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          T(rs(prof, 'username'), style: fs(F.title, 18)),
                          T('سطح ${fa(ri(prof, 'level'))} · امتیاز ${fa(ri(prof, 'rating'))} · 💎 ${fa(ri(prof, 'gems'))}', style: fs(F.body, 11, color: C.dim)),
                          Padding(padding: const EdgeInsets.only(top: 6), child: Bar(v: levelProgress(ri(prof, 'xp')).frac, h: 6)),
                          T('${fa(ri(prof, 'wins'))} برد · ${fa(ri(prof, 'losses'))} باخت · ${fa(ri(prof, 'goals'))} گل', style: fs(F.body, 10, color: C.dim)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            Title2('پروفایل آفلاین', en: 'OFFLINE CAREER', accent: hex('#ff7bd5')),
            Enter(
              i: 1,
              child: Panel(
                accent: hex('#ff7bd5'),
                pad: const EdgeInsets.all(14),
                child: Row(textDirection: TextDirection.rtl, children: [
                  Container(
                    width: 72, height: 72, alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 2.5), color: BG0, boxShadow: glow(C.cyan, 12, .5)),
                    child: ClipOval(child: Img(teamImg(teamKey(t)), w: 66, h: 66)),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        TextField(
                          controller: name,
                          maxLength: 16,
                          textAlign: TextAlign.right,
                          style: fs(F.title, 18),
                          decoration: const InputDecoration(counterText: '', isDense: true, filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
                          onSubmitted: (v) => Store.I.set((q) => q.name = v.trim().isEmpty ? 'Pilot' : v.trim()),
                          onTapOutside: (_) {
                            FocusScope.of(context).unfocus();
                            Store.I.set((q) => q.name = name.text.trim().isEmpty ? 'Pilot' : name.text.trim());
                          },
                        ),
                        T('برای تغییر نام لمس کن', style: fs(F.body, 10, color: C.dim)),
                        Padding(padding: const EdgeInsets.only(top: 6), child: T('سطح ${fa(lv.level)}', style: fs(F.bold, 12, color: C.gold))),
                        Bar(v: lv.cur / lv.need, h: 6),
                        T('${lv.cur} / ${lv.need} XP', style: fs(F.body, 10, color: C.dim)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Panel(
              accent: C.gold,
              pad: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                T('لیگ ${LEAGUE_FA[lg.name]}', style: fs(F.bold, 14, color: C.gold)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Bar(v: (p.trophies - lg.from) / (lg.to - lg.from), color: C.gold, color2: C.orange)),
                T('${fa(p.trophies)} از ${fa(lg.to)} جام', style: fs(F.body, 11, color: C.dim)),
              ]),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.05,
              children: [
                for (final (img, l, v) in stats)
                  Panel(noAccent: true, pad: const EdgeInsets.all(8), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 36, h: 36), T(fa(v), style: fs(F.title, 16)), T(l, style: fs(F.body, 10, color: C.dim))])),
              ],
            ),
            Title2('دستاوردها', en: 'ACHIEVEMENTS', accent: C.green),
            for (final (i, a) in ACHS.indexed)
              Enter(
                i: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: () {
                    final cur = a.cur(p).clamp(0, a.max), done = cur >= a.max, got = p.claimedAch.contains(a.id);
                    return Panel(
                      accent: done && !got ? C.green : null,
                      noAccent: !(done && !got),
                      glow: done && !got,
                      pad: const EdgeInsets.all(10),
                      child: Row(textDirection: TextDirection.rtl, children: [
                        Img(UI2[a.icon], w: 44, h: 44),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              T(a.name, style: fs(F.bold, 13)),
                              T(a.desc, style: fs(F.body, 10, color: C.dim)),
                              Padding(padding: const EdgeInsets.only(top: 4), child: Bar(v: cur / a.max, h: 5, color: done ? C.green : C.cyan)),
                              T('${fa(cur)}/${fa(a.max)}', style: fs(F.body, 10, color: C.dim)),
                            ]),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: got
                              ? T('✓ دریافت شد', align: TextAlign.center, style: fs(F.body, 10, color: C.green))
                              : done
                                  ? Btn(label: '+${a.coins}', small: true, colors: G.green, onPress: () => claim(a))
                                  : T('+${a.coins}', align: TextAlign.center, style: fs(F.bold, 11, color: C.gold)),
                        ),
                      ]),
                    );
                  }(),
                ),
              ),
          ]);
        },
      );
}
