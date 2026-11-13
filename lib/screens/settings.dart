// Settings sheet — port of src/screens/Settings.tsx (+ physics backend picker for offline matches).
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/forge_engine.dart';
import '../i18n/i18n.dart';
import '../prefs.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'account.dart';

class SettingsSheet extends StatefulWidget {
  final Toast toast;
  final VoidCallback replayIntro, onUiChanged;
  const SettingsSheet({super.key, required this.toast, required this.replayIntro, required this.onUiChanged});
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool sure = false;

  Widget _panel(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Panel(noAccent: true, pad: const EdgeInsets.all(12), child: child));
  Widget _title(String s, [String? sub]) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        T(s, style: fs(F.bold, 15)),
        if (sub != null) T(sub, style: fs(F.body, 11, color: C.dim)),
        const SizedBox(height: 8),
      ]);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.I,
      builder: (context, _) {
        final p = Store.I.p, st = Store.I;
        final rows = [
          (UI2['c_mega'], 'صداها', 'ضربه، گل، تماشاگر', p.sound, (bool v) => st.set((q) => q.sound = v)),
          (UI2['c_bell'], 'موسیقی', 'موسیقی منو', p.music, (bool v) => st.set((q) => q.music = v)),
          (UI2['x_gear'], 'لرزش', 'بازخورد لمسی هنگام برخورد', p.haptics, (bool v) => st.set((q) => q.haptics = v)),
          (ORACLE['idle'], 'نمایش اوراکل', 'دستیار شناور، مربی بازی و راهنما', p.oracle, (bool v) => st.set((q) => q.oracle = v)),
        ];
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
          Enter(
            i: 0,
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('ظاهر و زبان'),
              Segment<ThemeName>(value: uiTheme, accent: C.violet, items: const [(ThemeName.dark, 'تم تیره'), (ThemeName.light, 'تم روشن')], onChange: (v) async {
                await setUiPref(theme: v);
                widget.onUiChanged();
              }),
              const SizedBox(height: 8),
              Segment<Lang>(value: LANG, accent: C.cyan, items: const [(Lang.fa, 'فارسی'), (Lang.en, 'English')], onChange: (v) async {
                await setUiPref(lang: v);
                widget.onUiChanged();
              }),
              Padding(padding: const EdgeInsets.only(top: 6), child: T('با تغییر، برنامه یک لحظه دوباره بارگذاری می‌شود', align: TextAlign.right, style: fs(F.body, 11, color: C.dim))),
            ])),
          ),
          Enter(i: 0, child: AccountPanel(toast: widget.toast)),
          for (final (i, (img, n, d, on, set)) in rows.indexed)
            Enter(
              i: i,
              child: _panel(Row(textDirection: TextDirection.rtl, children: [
                Img(img, w: 44, h: 44),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [T(n, style: fs(F.bold, 15)), T(d, style: fs(F.body, 11, color: C.dim))]),
                  ),
                ),
                Toggle(on: on, onChange: set),
              ])),
            ),
          Enter(
            i: 3,
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('بلندی صدا'),
              Segment<double>(value: p.volume, items: const [(.25, '۲۵٪'), (.5, '۵۰٪'), (.75, '۷۵٪'), (1.0, '۱۰۰٪')], onChange: (v) => st.set((q) => q.volume = v)),
            ])),
          ),
          Enter(
            i: 3,
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('کیفیت گرافیک', 'روی گوشی‌های ضعیف «روان» را انتخاب کن'),
              Segment<String>(value: p.quality, accent: C.violet, items: const [('high', 'بالا'), ('low', 'روان')], onChange: (v) => st.set((q) => q.quality = v)),
            ])),
          ),
          Enter(
            i: 4,
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('موتور فیزیک (آفلاین)', forge2dReady ? 'کلاسیک = همان حس نسخه‌ی اصلی · Box2D = موتور Forge2D · بازی آنلاین همیشه کلاسیک' : 'Box2D روی این دستگاه در دسترس نیست'),
              Segment<String>(value: p.physics, accent: C.green, items: const [('classic', 'کلاسیک'), ('forge2d', 'Box2D')], onChange: (v) => st.set((q) => q.physics = forge2dReady ? v : 'classic')),
            ])),
          ),
          Enter(
            i: 4,
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title('سختی پیش‌فرض ربات'),
              Segment<int>(value: p.aiLvl, items: const [(0, 'آسان'), (1, 'معمولی'), (2, 'سخت')], onChange: (v) => st.set((q) => q.aiLvl = v)),
            ])),
          ),
          const SizedBox(height: 8),
          Btn(label: 'پخش دوباره‌ی اینترو', small: true, colors: G.dark, onPress: widget.replayIntro),
          const SizedBox(height: 10),
          Btn(
            label: sure ? 'مطمئنی؟ دوباره بزن' : 'پاک کردن پیشرفت',
            small: true,
            colors: G.red,
            onPress: () {
              if (!sure) return setState(() => sure = true);
              st.reset();
              setState(() => sure = false);
              widget.toast('پیشرفت پاک شد', 'ok');
            },
          ),
          Padding(padding: const EdgeInsets.only(top: 24), child: T('NEXORA · Finger Soccer · v2.0.0 (Flutter)', align: TextAlign.center, style: fs(F.head, 10, ls: 2, color: C.dim2))),
        ]);
      },
    );
  }
}
