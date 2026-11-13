// Oracle event bus — the non-visual half of src/oracle/Oracle.tsx (say / react / coach / scene / quiet).
// The floating bubble, coach toast, tour and Q&A panel (oracle.dart) listen to this notifier.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum OracleEvent { goal, reward, levelup, purchase, nogems, error, search, challengeDone, message, follow, tourReady, matchFound }

class OracleMsg {
  final int id;
  final String text, mood;
  final List<String>? actions;
  OracleMsg(this.text, this.mood, [this.actions]) : id = DateTime.now().microsecondsSinceEpoch;
}

class OracleBus extends ChangeNotifier {
  OracleBus._();
  static final OracleBus I = OracleBus._();

  bool enabled = true;
  bool bubbleVisible = false; // set by the shell: tabs visible && scene == ui
  String scene = 'ui';
  OracleMsg? msg, coachMsg;
  String mood = 'idle';
  bool panelRequested = false;
  final Set<String> _quiet = {};
  final Map<OracleEvent, int> _last = {};
  Timer? _hide, _coachT;
  final _r = math.Random();

  void say(String text, [String m = 'content', List<String>? actions]) {
    mood = m;
    msg = OracleMsg(text, m, actions);
    _hide?.cancel();
    _hide = Timer(Duration(milliseconds: math.min(14000, 4500 + text.length * 55)), () {
      msg = null;
      mood = 'idle';
      notifyListeners();
    });
    notifyListeners();
  }

  void clear() {
    msg = null;
    mood = 'idle';
    notifyListeners();
  }

  void coach(String text, [String m = 'idea']) {
    if (!enabled) return;
    coachMsg = OracleMsg(text, m);
    _coachT?.cancel();
    _coachT = Timer(const Duration(milliseconds: 3600), () {
      coachMsg = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _announce(String text, String m, [List<String>? a]) => bubbleVisible ? say(text, m, a) : coach(text, m);

  static const _gap = {
    OracleEvent.goal: 3000, OracleEvent.reward: 2500, OracleEvent.levelup: 1000, OracleEvent.purchase: 2000, OracleEvent.nogems: 15000,
    OracleEvent.error: 20000, OracleEvent.search: 5000, OracleEvent.challengeDone: 4000, OracleEvent.message: 8000, OracleEvent.follow: 5000,
    OracleEvent.tourReady: 10000, OracleEvent.matchFound: 3000,
  };

  void react(OracleEvent ev, [String? detail]) {
    if (!enabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_last[ev] ?? 0) < _gap[ev]!) return;
    _last[ev] = now;
    if (ev == OracleEvent.message && _quiet.contains('chat')) return;
    switch (ev) {
      case OracleEvent.goal:
        coach(const ['گووووول! 🔥', 'چه ضربه‌ای! 😄', 'تور دروازه لرزید! ⚡'][_r.nextInt(3)], _r.nextBool() ? 'excited' : 'laugh');
      case OracleEvent.reward:
        _announce(detail != null ? 'جایزه رسید: $detail 🎁' : 'جایزه‌ات رسید! 🎁', 'joy');
      case OracleEvent.levelup:
        _announce(detail != null ? 'سطح $detail! داری قوی‌تر می‌شی کاپیتان 🚀' : 'سطح جدید! 🚀', 'spin');
      case OracleEvent.purchase:
        _announce('مبارکت باشه! با این یکی حسابی می‌درخشی ✨', 'happy');
      case OracleEvent.nogems:
        _announce('الماس کافی نداری 🤔 چالش‌های روزانه (تا ۵)، جایزه‌ی فصل (تا ۳۰) و قهرمانی تورنمنت (تا ۳۰) الماس می‌دن.', 'confused', ['challenges', 'tours']);
      case OracleEvent.error:
        _announce('اوه! ${detail ?? 'یه مشکلی پیش اومد'} — نگران نباش، دوباره امتحان می‌کنیم.', 'alert');
      case OracleEvent.search:
        coach('دارم حریف پیدا می‌کنم… 🔭', 'spin');
      case OracleEvent.challengeDone:
        _announce('چالش «${detail ?? ''}» کامل شد! جایزه‌ات رو بگیر 🎉', 'excited', ['claim']);
      case OracleEvent.message:
        _announce(detail != null ? 'پیام جدید از $detail 💬' : 'پیام جدید داری 💬', 'curious', ['messages']);
      case OracleEvent.follow:
        _announce(detail != null ? '$detail دنبالت کرد! 👀' : 'یک دنبال‌کننده‌ی جدید داری 👀', 'curious');
      case OracleEvent.tourReady:
        _announce('مسابقه‌ی تورنمنتت آماده‌ست! ⚠️ زود وارد شو.', 'alert', ['tours']);
      case OracleEvent.matchFound:
        coach('حریف پیدا شد! آماده باش ⚡', 'excited');
    }
  }

  VoidCallback setScene(String s) {
    scene = s;
    notifyListeners();
    return () {
      scene = 'ui';
      notifyListeners();
    };
  }

  void setQuiet(String k, bool on) => on ? _quiet.add(k) : _quiet.remove(k);

  void openPanel() {
    panelRequested = true;
    notifyListeners();
  }
}
