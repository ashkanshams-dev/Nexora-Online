import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../games/game_registry.dart';

/// Real global rankings: per-game rating (online matches) and overall XP.
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.initialGame});
  final String? initialGame;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String? _game; // null = global XP
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _game = widget.initialGame;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.isOnline) await o.ensureSession();
    final SupabaseClient? c = o.client;
    if (c == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<dynamic> rows = _game == null
          ? await c.from('nx_leaderboard_global').select().order('xp', ascending: false).limit(50)
          : await c
              .from('nx_leaderboard')
              .select()
              .eq('game', _game!)
              .order('rating', ascending: false)
              .order('won', ascending: false)
              .limit(50);
      if (!mounted) return;
      setState(() => _rows = rows.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = context.tx('بارگیری رتبه‌بندی ممکن نشد', 'Could not load rankings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? me = ref.watch(onlineProvider).uid;
    return NxWorldScaffold(
      title: context.tx('رتبه‌بندی جهانی', 'GLOBAL RANKINGS'),
      palette: WorldPalette.arcade,
      body: Column(children: <Widget>[
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NxSpace.md, vertical: 8),
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(context.tx('همه (XP)', 'All (XP)')),
                  selected: _game == null,
                  onSelected: (_) {
                    setState(() => _game = null);
                    _load();
                  },
                ),
              ),
              for (final GameInfo g in kGames)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(context.tx(g.nameFa, g.nameEn)),
                    selected: _game == g.id,
                    onSelected: (_) {
                      setState(() => _game = g.id);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              context.tx('هنوز کسی در این بخش بازی آنلاین ثبت نکرده. اولین نفر باش!',
                                  'No online results here yet. Be the first!'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(NxSpace.md),
                            itemCount: _rows.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Map<String, dynamic> r = _rows[i];
                              final bool mine = r['user_id'] == me;
                              final Color medal = i == 0
                                  ? NxColors.gold
                                  : i == 1
                                      ? const Color(0xFFC0C8D8)
                                      : i == 2
                                          ? const Color(0xFFCD8A55)
                                          : NxColors.textDim;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassPanel(
                                  borderColor: mine ? NxColors.turquoise : null,
                                  child: Row(children: <Widget>[
                                    SizedBox(
                                      width: 34,
                                      child: Text('${i + 1}',
                                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: medal)),
                                    ),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                        Text('${r['username'] ?? 'Pilot'}${mine ? context.tx(' (تو)', ' (you)') : ''}',
                                            style: const TextStyle(fontWeight: FontWeight.w800)),
                                        Text(
                                          context.tx('${r['won'] ?? 0} برد از ${r['played'] ?? 0} بازی آنلاین',
                                              '${r['won'] ?? 0} wins of ${r['played'] ?? 0} online games'),
                                          style: const TextStyle(color: NxColors.textDim, fontSize: 12),
                                        ),
                                      ]),
                                    ),
                                    Text(
                                      _game == null ? 'XP ${r['xp'] ?? 0}' : '${r['rating'] ?? 1000}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, color: NxColors.gold),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
