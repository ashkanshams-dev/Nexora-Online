import 'dart:async';

import 'package:flutter/material.dart';

import 'oracle_persona.dart';
import 'oracle_persona_store.dart';

/// Funny-but-accurate tutorial card shown at the start of a game (only for mechanics the player has not seen enough;
/// replayable from the game's ORACLE sheet). Never blocks input: it sits at the top and fades out by itself.
class OracleTutorialBanner extends StatefulWidget {
  const OracleTutorialBanner({super.key, required this.gameId, this.delay = const Duration(milliseconds: 1400)});
  final String gameId;
  final Duration delay;

  @override
  State<OracleTutorialBanner> createState() => _OracleTutorialBannerState();
}

class _OracleTutorialBannerState extends State<OracleTutorialBanner> {
  OracleTutorial? _t;
  Timer? _in, _out;

  @override
  void initState() {
    super.initState();
    _in = Timer(widget.delay, () {
      if (!mounted) return;
      final OracleTutorial? t = OraclePersona.instance.nextTutorial(widget.gameId, OraclePersonaStore.tutorialViews());
      if (t == null) return;
      OraclePersonaStore.markTutorial(t);
      setState(() => _t = t);
      _out = Timer(const Duration(seconds: 9), _hide);
    });
  }

  void _hide() {
    if (mounted) setState(() => _t = null);
  }

  @override
  void dispose() {
    _in?.cancel();
    _out?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OracleTutorial? t = _t;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: t == null
          ? const SizedBox.shrink()
          : GestureDetector(key: ValueKey<String>(t.key), onTap: _hide, child: OracleTutorialCard(tutorial: t)),
    );
  }
}

class OracleTutorialCard extends StatelessWidget {
  const OracleTutorialCard({super.key, required this.tutorial});
  final OracleTutorial tutorial;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 56),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: <Color>[Color(0xF2182A5E), Color(0xF22A1556)]),
            border: Border.all(color: const Color(0xFF39E6FF)),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x6639E6FF), blurRadius: 18)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Image.asset('assets/characters/oracle/moods/laugh.webp',
                width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text('ORACLE · ${tutorial.title}',
                    style: const TextStyle(color: Color(0xFF8FF3FF), fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tutorial.line,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1.35)),
                const SizedBox(height: 4),
                Text(tutorial.how, style: const TextStyle(color: Color(0xFFC9D3FF), fontSize: 12, height: 1.35)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ORACLE's reaction line on the result screen (computed from the real result).
class OracleResultLine extends StatelessWidget {
  const OracleResultLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Image.asset('assets/characters/oracle/moods/laugh.webp',
            width: 34, height: 34, errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF))),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xCC1B2350),
              border: Border.all(color: const Color(0xFF39E6FF).withValues(alpha: .7)),
            ),
            child: Text(text,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.4)),
          ),
        ),
      ]),
    );
  }
}
