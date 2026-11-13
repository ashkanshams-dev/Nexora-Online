// Broadcast-style match scoreboard — port of src/ui/ScoreBug.tsx
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/util.dart';
import 'kit.dart';
import 'theme.dart';

class BugSide {
  final Team team;
  final String name;
  final int score;
  final Color color;
  final bool on;
  final String? avatar; // optional override (online disc art)
  const BugSide({required this.team, required this.name, required this.score, required this.color, required this.on, this.avatar});
}

String teamCode(Team t) {
  final words = t.name.replaceAll(RegExp(r'[^A-Za-z ]'), '').split(' ').where((w) => w.isNotEmpty).toList();
  final s = words.length > 1
      ? t.name.split(' ').where((w) => RegExp(r'[A-Za-z]').hasMatch(w) && w != 'II').map((w) => w[0]).join()
      : t.name.replaceAll(RegExp(r'[^A-Za-z]'), '');
  final c = (s.length > 3 ? s.substring(0, 3) : s).toUpperCase();
  return c.isEmpty ? 'NXG' : c;
}

class _Wing extends StatelessWidget {
  final BugSide s;
  final bool right, timed;
  final double tl;
  const _Wing(this.s, {this.right = false, required this.tl, required this.timed});
  @override
  Widget build(BuildContext context) {
    final c = s.color;
    final grad = [c.withValues(alpha: s.on ? .8 : .27), c.withValues(alpha: s.on ? .53 : .2), rgba(6, 9, 26, .94)];
    return Expanded(
      child: Stack(children: [
        Positioned.fill(child: AnimatedContainer(duration: const Duration(milliseconds: 300), decoration: BoxDecoration(gradient: LinearGradient(colors: right ? grad.reversed.toList() : grad)))),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(textDirection: right ? TextDirection.rtl : TextDirection.ltr, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hex('#04060f'),
                  border: Border.all(color: s.on ? Colors.white : const Color(0x40FFFFFF), width: 1.5),
                  boxShadow: s.on ? [BoxShadow(color: c, blurRadius: 8)] : null,
                ),
                alignment: Alignment.center,
                child: ClipOval(child: Img(s.avatar ?? TEAM_IMG[teamKey(s.team)], w: 34, h: 34, fit: BoxFit.cover)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                    T(teamCode(s.team), style: fs(F.title, 15, ls: 1.5, color: Colors.white)),
                    T(s.name, n: 1, style: fs(F.body, 10, color: s.on ? Colors.white : rgba(225, 235, 255, .6))),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        if (s.on)
          Positioned(
            left: 6, right: 6, bottom: 3,
            child: Container(
              height: 3,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0x2EFFFFFF)),
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (timed ? tl : 1.0).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: timed && tl < .25 ? C.red : Colors.white)),
              ),
            ),
          ),
      ]),
    );
  }
}

class ScoreBug extends StatelessWidget {
  final BugSide left, right;
  final String clock;
  final bool sudden, timed;
  final double tl;
  final String? status;
  const ScoreBug({super.key, required this.left, required this.right, required this.clock, required this.sudden, required this.tl, required this.timed, this.status});

  Widget _score(BugSide s) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
        child: SizedBox(
          key: ValueKey(s.score),
          width: 22,
          child: Text('${s.score}',
              textAlign: TextAlign.center, style: fs(F.title, 26, color: Colors.white, shadows: s.on ? [Shadow(color: s.color, blurRadius: 10)] : null)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x24FFFFFF)),
            color: rgba(5, 8, 22, .92),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            _Wing(left, tl: tl, timed: timed),
            Container(
              width: 92,
              decoration: BoxDecoration(
                border: const Border.symmetric(vertical: BorderSide(color: Color(0x1FFFFFFF))),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [hex('#1a2350'), hex('#0a0f2a'), hex('#05081a')]),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _score(left),
                Container(width: 8, height: 3, margin: const EdgeInsets.symmetric(horizontal: 7), decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0x8CFFFFFF))),
                _score(right),
              ]),
            ),
            _Wing(right, right: true, tl: tl, timed: timed),
          ]),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: sudden ? C.gold : rgba(5, 8, 22, .92),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            border: Border(left: BorderSide(color: sudden ? C.gold : const Color(0x24FFFFFF)), right: BorderSide(color: sudden ? C.gold : const Color(0x24FFFFFF)), bottom: BorderSide(color: sudden ? C.gold : const Color(0x24FFFFFF))),
          ),
          alignment: Alignment.center,
          child: T(sudden ? 'GOLDEN GOAL' : (clock.isEmpty ? '00:00' : clock), style: fs(F.head, 11, ls: 2, color: sudden ? hex('#1b1200') : hex('#e6eeff'))),
        ),
        if (status != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: rgba(5, 8, 22, .75), border: Border.all(color: const Color(0x24FFFFFF))),
            child: T(status!, n: 1, style: fs(F.bold, 11, color: Colors.white)),
          ),
      ]),
    );
  }
}
