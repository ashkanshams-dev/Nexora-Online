// Port of src/ui/theme.ts — colours, gradients, fonts and design tokens (identical values).
import 'package:material_ui/material_ui.dart';

import '../i18n/i18n.dart';

Color hex(String s, [double a = 1]) {
  var h = s.replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final v = int.parse(h.substring(0, 6), radix: 16);
  final alpha = h.length == 8 ? int.parse(h.substring(6, 8), radix: 16) / 255 : 1.0;
  return Color(0xFF000000 | v).withValues(alpha: alpha * a);
}

Color rgba(int r, int g, int b, double a) => Color.fromARGB((a * 255).round(), r, g, b);

/// palette (mutable so the light theme can be applied at boot, like Object.assign(C, …) in RN)
class C {
  static Color bg = hex('#030614');
  static Color bg2 = hex('#060b22');
  static Color panel = rgba(14, 22, 58, 0.78);
  static Color panel2 = rgba(8, 12, 34, 0.9);
  static Color glass = rgba(14, 24, 64, 0.62);
  static Color line = rgba(110, 170, 255, 0.24);
  static Color lineHi = rgba(120, 220, 255, 0.75);
  static Color cyan = hex('#4fe3ff');
  static Color sky = hex('#7fc8ff');
  static Color blue = hex('#3b82ff');
  static Color indigo = hex('#6d5bff');
  static Color violet = hex('#a35bff');
  static Color pink = hex('#ff4fa3');
  static Color gold = hex('#ffd257');
  static Color orange = hex('#ff8a3a');
  static Color red = hex('#ff4a5a');
  static Color green = hex('#3dffa8');
  static Color text = hex('#eef4ff');
  static Color dim = hex('#93a7d8');
  static Color dim2 = hex('#5f6f9e');
}

/// font roles (RN: Orbitron 900/700, Exo2 600/800, Vazirmatn 500/800)
enum F { title, head, body, bold, fa, faB }

TextStyle fs(F f, double size, {Color? color, double? ls, double? height, List<Shadow>? shadows}) {
  final (fam, w) = switch (f) {
    F.title => ('Orbitron', 900),
    F.head => ('Orbitron', 700),
    F.body => ('Exo2', 600),
    F.bold => ('Exo2', 800),
    F.fa => ('Vazirmatn', 500),
    F.faB => ('Vazirmatn', 800),
  };
  return TextStyle(
    fontFamily: fam,
    fontSize: size,
    fontWeight: FontWeight.values[(w ~/ 100) - 1],
    fontVariations: [FontVariation('wght', w.toDouble())],
    color: color ?? C.text,
    letterSpacing: ls,
    height: height,
    shadows: shadows,
  );
}

class G {
  static List<Color> get primary => [C.cyan, hex('#5b8cff'), C.violet];
  static final gold = [hex('#8a5200'), hex('#d39420'), hex('#ffe08a')];
  static final green = [hex('#0a6b4a'), hex('#16b77a'), hex('#5dffbf')];
  static final red = [hex('#5a0f24'), hex('#a3203f'), hex('#ff5b74')];
  static final dark = [hex('#151f4a'), hex('#1d2b63'), hex('#2a3f86')];
  static final violet = [hex('#3a1d8a'), hex('#6d3bff'), hex('#c08bff')];
}

String faNum(Object s) {
  if (LANG == Lang.en) return '$s';
  const d = '۰۱۲۳۴۵۶۷۸۹';
  return '$s'.replaceAllMapped(RegExp(r'\d'), (m) => d[int.parse(m[0]!)]);
}

String fa(num n) {
  final s = n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => LANG == Lang.en ? ',' : '٬');
  return faNum(s);
}

enum ThemeName { dark, light }

ThemeName THEME = ThemeName.dark;
bool isLight() => THEME == ThemeName.light;
void applyTheme(ThemeName t) {
  THEME = t;
  if (t != ThemeName.light) return;
  C.bg = hex('#eef3fc');
  C.bg2 = hex('#e2eaf8');
  C.panel = rgba(255, 255, 255, .86);
  C.panel2 = rgba(246, 249, 255, .95);
  C.glass = rgba(255, 255, 255, .72);
  C.line = rgba(40, 70, 140, .18);
  C.lineHi = rgba(30, 120, 220, .6);
  C.cyan = hex('#0796c9');
  C.sky = hex('#2b74d6');
  C.blue = hex('#2f6bff');
  C.indigo = hex('#5546e8');
  C.violet = hex('#7c3bea');
  C.pink = hex('#d92c80');
  C.gold = hex('#b07800');
  C.orange = hex('#d9601a');
  C.red = hex('#dc2f44');
  C.green = hex('#0a9a62');
  C.text = hex('#0e1a3a');
  C.dim = hex('#4a5a84');
  C.dim2 = hex('#7b88aa');
}

const BG0 = Color(0xFF05040E);

class SP {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32;
}

class RR {
  static const double s = 10, m = 14, l = 20, xl = 26, pill = 999;
}

class TY {
  static const double tiny = 10, cap = 11, small = 12, body = 14, h3 = 16, h2 = 19, h1 = 24, hero = 30;
}

class IC {
  static const double s = 20, m = 24, l = 28;
}

const double ICON_ART = 40;
const double TOUCH = 44;

List<BoxShadow> glow(Color color, [double r = 14, double o = .6]) => [BoxShadow(color: color.withValues(alpha: o), blurRadius: r)];
const List<BoxShadow> depth = [BoxShadow(color: Color(0x8C000000), blurRadius: 14, offset: Offset(0, 8))];

/// Material 3 theme seeded from the NEXORA palette (used by M3 widgets: dialogs, text fields, sliders…)
ThemeData nexoraTheme() {
  final dark = !isLight();
  final scheme = ColorScheme.fromSeed(
    seedColor: C.cyan,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: C.cyan,
    secondary: C.violet,
    tertiary: C.gold,
    error: C.red,
    surface: dark ? hex('#0b1236') : C.bg,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? hex('#02030b') : C.bg,
    fontFamily: 'Exo2',
    fontFamilyFallback: const ['Vazirmatn'],
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: rgba(6, 10, 30, .8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.cyan, width: 1.4)),
    ),
  );
}
