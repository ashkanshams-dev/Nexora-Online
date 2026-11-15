// v0.6.2 Premium Ultra badge: a small magenta -> gold gradient pill with a glow, shown on Ultra discs in the shop
// and in My Teams (team screen) so the tier reads at a glance.
import 'package:flutter/material.dart';

import '../game/data.dart';

bool isUltra(Team t) => t.cat == 'ultra';

class UltraBadge extends StatelessWidget {
  final double size;
  const UltraBadge({super.key, this.size = 9});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * .6, vertical: size * .18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xffff3df2), Color(0xff9b5cff), Color(0xffffd257)]),
          borderRadius: BorderRadius.circular(size),
          border: Border.all(color: const Color(0xccffffff), width: .8),
          boxShadow: const [BoxShadow(color: Color(0x99ff3df2), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: size * 1.1, color: Colors.white),
          SizedBox(width: size * .25),
          Text('ULTRA', style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: .6, height: 1.1, decoration: TextDecoration.none)),
        ]),
      );
}
