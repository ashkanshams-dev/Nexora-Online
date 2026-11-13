// First screen for anyone not signed in — port of src/screens/Welcome.tsx.
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../i18n/i18n.dart';
import '../prefs.dart';
import '../ui/kit.dart';
import '../ui/space.dart';
import '../ui/theme.dart';
import 'account.dart';

class Welcome extends StatelessWidget {
  final Toast toast;
  final VoidCallback onUiChanged;
  const Welcome({super.key, required this.toast, required this.onUiChanged});
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Material(
      color: C.bg,
      child: Stack(children: [
        const Positioned.fill(child: Space(theme: SpaceTheme.stadium, dim: .1)),
        ListView(padding: EdgeInsets.fromLTRB(18, ins.top + 16, 18, ins.bottom + 24), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 150, child: Segment<Lang>(value: LANG, accent: C.cyan, items: const [(Lang.fa, 'FA'), (Lang.en, 'EN')], onChange: (v) async {
              await setUiPref(lang: v);
              onUiChanged();
            })),
          ),
          Column(children: [
            Img(UI['logo_nexora'], w: 240, h: 120),
            Padding(padding: const EdgeInsets.only(top: 6), child: T('به نکسورا خوش آمدی', align: TextAlign.center, style: fs(F.title, 22))),
            Padding(padding: const EdgeInsets.only(top: 6), child: T('حساب بساز تا پیشرفت، دیسک‌ها و دوستانت روی هر گوشی همراهت باشند.', align: TextAlign.center, style: fs(F.body, 13, color: C.dim, height: 1.6))),
          ]).animate(delay: 80.ms).fadeIn().slideY(begin: .2, curve: Curves.easeOutBack),
          Padding(padding: const EdgeInsets.only(top: 18), child: AccountPanel(toast: toast)).animate(delay: 180.ms).fadeIn().slideY(begin: .2, curve: Curves.easeOutBack),
        ]),
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }
}
