// v0.6.1 in-match formation picker (captain changes formation mid-match; applied at the next kick-off / reset).
// Used by the offline pause menu and the online match screen.
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../game/data.dart';
import '../ui/kit.dart';

/// Opens a bottom sheet with the six formations; resolves to the picked index (null = dismissed).
Future<int?> pickFormation(BuildContext context, {required int current, String? title}) => showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (cc) => FormationPicker(current: current, title: title, onPick: (i) => Navigator.pop(cc, i)),
    );

class FormationPicker extends StatelessWidget {
  final int current;
  final String? title;
  final ValueChanged<int> onPick;
  const FormationPicker({super.key, required this.current, required this.onPick, this.title});

  @override
  Widget build(BuildContext context) {
    final b = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, b + 14),
      decoration: const BoxDecoration(
        color: Color(0xf2080c22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: Color(0x5578dcff))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        tTitle(title ?? 'تغییر ترکیب', size: 18, align: TextAlign.center),
        const SizedBox(height: 2),
        const T('از شروع بعدی بازی اعمال می‌شود', size: 11, color: C.dim, align: TextAlign.center),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.rtl,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .78,
            children: [
              for (var i = 0; i < kForms.length; i++)
                Press(
                  key: ValueKey('fpick$i'),
                  onTap: () => onPick(i),
                  child: Column(children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: i == current ? C.cyan : const Color(0x33ffffff), width: i == current ? 2.4 : 1)),
                        clipBehavior: Clip.antiAlias,
                        child: CustomPaint(painter: MiniFormationPainter(i), child: const SizedBox.expand()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    tBold(kForms[i].code, size: 12, align: TextAlign.center, color: i == current ? C.cyan : C.text),
                    T(kForms[i].name, size: 9, color: C.dim2, align: TextAlign.center),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Mini pitch with the formation's slots (own half at the bottom).
class MiniFormationPainter extends CustomPainter {
  final int form;
  MiniFormationPainter(this.form);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xff2f7d22));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xb3ffffff);
    c.drawRect(Rect.fromLTWH(3, 3, s.width - 6, s.height - 6), line);
    c.drawLine(Offset(3, s.height / 2), Offset(s.width - 3, s.height / 2), line);
    c.drawCircle(Offset(s.width / 2, s.height / 2), s.width * .14, line);
    final dot = Paint()..color = const Color(0xff3bd0ff);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white;
    for (final pt in slots(form)) {
      final o = Offset(8 + pt[0] * (s.width - 16), s.height - 3 - pt[1] * (s.height - 6));
      c.drawCircle(o, 4.5, dot);
      c.drawCircle(o, 4.5, rim);
    }
  }

  @override
  bool shouldRepaint(MiniFormationPainter o) => o.form != form;
}
