import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import 'oracle_persona.dart';
import 'oracle_persona_data.dart';
import 'oracle_persona_store.dart';

/// Admin: edit ORACLE's personality config (players & aliases, lines, greetings, spontaneous lines, reactions,
/// tutorials, tour texts, frequencies, cooldowns, category switches). Saved to Supabase (`nx_oracle_persona_save`,
/// owner / 'oracle' permission only, audited); every app picks it up on its next refresh.
class OracleConfigPage extends ConsumerStatefulWidget {
  const OracleConfigPage({super.key});

  @override
  ConsumerState<OracleConfigPage> createState() => _OracleConfigPageState();
}

class _OracleConfigPageState extends ConsumerState<OracleConfigPage> {
  final TextEditingController _c = TextEditingController();
  bool _loading = true, _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SupabaseClient? c = ref.read(onlineProvider).client;
    Map<String, dynamic> data = Map<String, dynamic>.from(kOraclePersonaDefaults);
    try {
      final Map<String, dynamic>? row = await c?.from('nx_oracle_persona').select('data, version').eq('id', 1).maybeSingle();
      final Object? d = row?['data'];
      if (d is Map && d.isNotEmpty) data = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _c.text = const JsonEncoder.withIndent('  ').convert(data);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final SupabaseClient? c = ref.read(onlineProvider).client;
    if (c == null) return;
    Map<String, dynamic> data;
    try {
      final Object? j = jsonDecode(_c.text);
      if (j is! Map) throw const FormatException('not an object');
      data = Map<String, dynamic>.from(j);
      OraclePersona(config: data); // validates that the engine accepts it
    } catch (e) {
      setState(() => _msg = 'JSON نامعتبر: $e');
      return;
    }
    setState(() => _saving = true);
    final String? err = await OraclePersonaStore.save(c, data);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _msg = err == null ? 'ذخیره شد ✓ — همه‌ی گوشی‌ها در رفرش بعدی می‌گیرند.' : 'خطا: $err';
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F26),
      appBar: AppBar(
        title: const Text('تنظیمات شخصیت اوراکل'),
        actions: <Widget>[
          IconButton(
            tooltip: 'پیش‌فرض',
            icon: const Icon(Icons.restore_rounded),
            onPressed: () => setState(() => _c.text = const JsonEncoder.withIndent('  ').convert(kOraclePersonaDefaults)),
          ),
          IconButton(
            tooltip: 'ذخیره',
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
            onPressed: _saving || _loading ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _msg ??
                      'بازیکن‌ها و نام‌های مستعار، جمله‌ها، خوشامدها، جمله‌های خودجوش، واکنش برد/باخت، آموزش‌ها، متن تورها، '
                          'احتمال‌ها و فاصله‌ها (freq) و روشن/خاموش هر بخش (enabled). {jan} = «جاااااااااان».',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: Color(0xFF8FF3FF), fontSize: 12),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _c,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF0E1838)),
                  ),
                ),
              ),
            ]),
    );
  }
}
