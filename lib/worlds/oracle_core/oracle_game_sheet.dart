import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/backend_gateway.dart';
import '../../core/backend/supabase_backend.dart';
import '../../core/ui2/oracle_mascot.dart';
import '../../games/game_registry.dart';
import 'persona/oracle_persona.dart';
import 'persona/oracle_persona_store.dart';

/// In-game ORACLE: rules, a hint, coaching and free questions about the current game (nx-oracle, mode=game).
/// Offline / no session → the game's bundled rules text.
class OracleGameSheet extends ConsumerStatefulWidget {
  const OracleGameSheet({super.key, required this.game, this.state});
  final GameInfo game;
  final Map<String, dynamic>? state;

  static Future<void> show(BuildContext context, GameInfo game, {Map<String, dynamic>? state}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OracleGameSheet(game: game, state: state),
    );
  }

  @override
  ConsumerState<OracleGameSheet> createState() => _OracleGameSheetState();
}

class _OracleGameSheetState extends ConsumerState<OracleGameSheet> {
  final List<Map<String, String>> _msgs = <Map<String, String>>[];
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty || _busy) return;
    setState(() {
      _msgs.add(<String, String>{'role': 'user', 'content': q.trim()});
      _busy = true;
    });
    _input.clear();
    String? answer;
    final BackendGateway be = ref.read(backendProvider);
    if (be is SupabaseBackend) {
      try {
        final Map<String, dynamic>? r = await be.oracleInvoke(<String, dynamic>{
          'messages': _msgs,
          'ctx': <String, dynamic>{
            'mode': 'game',
            'game': widget.game.id,
            'lang': _fa ? 'fa' : 'en',
            if (widget.state != null) 'state': widget.state,
            'persona': OraclePersona.instance.aiContext(q),
          },
        });
        final Object? m = r?['message'];
        if (m is Map) answer = '${m['content'] ?? ''}'.trim();
      } catch (_) {}
    }
    answer ??= '';
    if (answer.isEmpty) {
      answer = _fa
          ? 'الان به هوش آنلاین ORACLE وصل نیستم. قوانین ${widget.game.nameFa}:\n${widget.game.rulesFa}'
          : "I can't reach ORACLE online right now. ${widget.game.nameEn} rules:\n${widget.game.rulesEn}";
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(<String, String>{'role': 'assistant', 'content': answer!});
      _busy = false;
    });
  }

  /// Replays ORACLE's funny tutorials for this game (local, always accurate to the real controls).
  void _tutorials() {
    final List<OracleTutorial> all = OraclePersona.instance.tutorials(widget.game.id);
    setState(() {
      if (all.isEmpty) {
        _msgs.add(<String, String>{'role': 'assistant', 'content': widget.game.rulesFa});
        return;
      }
      for (final OracleTutorial t in all) {
        _msgs.add(<String, String>{'role': 'assistant', 'content': '${t.title}\n${t.line}\n${t.how}'});
        OraclePersonaStore.markTutorial(t);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> quick = _fa
        ? <(String, String)>[
            ('قوانین', 'قوانین این بازی را خلاصه و واضح توضیح بده.'),
            ('راهنمایی', 'برای حرکت بعدی‌ام یک راهنمایی بده.'),
            ('مربی', 'مثل یک مربی سه نکته‌ی مهم برای بهتر بازی کردن بگو.'),
          ]
        : <(String, String)>[
            ('Rules', 'Explain the rules of this game briefly and clearly.'),
            ('Hint', 'Give me a hint for my next move.'),
            ('Coach', 'As a coach, give me three key tips to play better.'),
          ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.62,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Color(0xFF13204A), Color(0xFF0A0F26)]),
          boxShadow: <BoxShadow>[BoxShadow(color: Color(0x5539E6FF), blurRadius: 30)],
          border: Border(top: BorderSide(color: Color(0xFF39E6FF), width: 1.2)),
        ),
        child: Column(children: <Widget>[
          const SizedBox(height: 8),
          Row(children: <Widget>[
            const SizedBox(width: 12),
            SizedBox(width: 56, height: 56, child: OracleMascot(mood: _busy ? OracleMood.think : OracleMood.happy)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('ORACLE · ${_fa ? widget.game.nameFa : widget.game.nameEn}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white70)),
          ]),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ActionChip(
                  label: Text(_fa ? 'آموزش ORACLE 😂' : 'ORACLE tutorial'),
                  onPressed: _busy ? null : _tutorials,
                  backgroundColor: const Color(0xFF3A1F63),
                  labelStyle: const TextStyle(color: Color(0xFFFFD27A)),
                  side: const BorderSide(color: Color(0x66FFC857)),
                ),
              ),
              for (final (String l, String q) in quick)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ActionChip(
                    label: Text(l),
                    onPressed: _busy ? null : () => _ask(q),
                    backgroundColor: const Color(0xFF1C2D63),
                    labelStyle: const TextStyle(color: Color(0xFF8FF3FF)),
                    side: const BorderSide(color: Color(0x6639E6FF)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length + (_busy ? 1 : 0),
              itemBuilder: (BuildContext context, int i) {
                if (i >= _msgs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                final Map<String, String> m = _msgs[i];
                final bool me = m['role'] == 'user';
                return Align(
                  alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                    decoration: BoxDecoration(
                      color: me ? const Color(0xFF2B1F5C) : const Color(0xFF12305A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: me ? const Color(0x66B57CFF) : const Color(0x6639E6FF)),
                    ),
                    child: Text(m['content'] ?? '', style: const TextStyle(color: Colors.white, height: 1.45)),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: InputDecoration(
                      hintText: _fa ? 'از ORACLE بپرس…' : 'Ask ORACLE…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF0E1838),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : () => _ask(_input.text),
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
