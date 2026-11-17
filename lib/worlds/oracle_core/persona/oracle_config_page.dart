import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import 'json_form_editor.dart';
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
  Map<String, dynamic> _data = <String, dynamic>{};
  bool _loading = true, _saving = false, _json = false, _dirty = false;
  int _formKey = 0;
  String? _msg;

  static Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SupabaseClient? c = ref.read(onlineProvider).client;
    Map<String, dynamic> data = _copy(kOraclePersonaDefaults);
    try {
      final Map<String, dynamic>? row = await c?.from('nx_oracle_persona').select('data, version').eq('id', 1).maybeSingle();
      final Object? d = row?['data'];
      if (d is Map && d.isNotEmpty) data = _copy(Map<String, dynamic>.from(d));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  /// Switch between the form and the raw JSON (advanced); the JSON text is parsed back when leaving it.
  bool _toggleJson() {
    if (_json) {
      try {
        final Object? j = jsonDecode(_c.text);
        if (j is! Map) throw const FormatException('not an object');
        _data = _copy(Map<String, dynamic>.from(j));
      } catch (e) {
        setState(() => _msg = 'JSON نامعتبر: $e');
        return false;
      }
    } else {
      _c.text = const JsonEncoder.withIndent('  ').convert(_data);
    }
    setState(() {
      _json = !_json;
      _formKey++;
    });
    return true;
  }

  Future<void> _save() async {
    final SupabaseClient? c = ref.read(onlineProvider).client;
    if (c == null) return;
    if (_json && !_toggleJson()) return;
    try {
      OraclePersona(config: _data); // validates that the engine accepts it
    } catch (e) {
      setState(() => _msg = 'تنظیمات نامعتبر: $e');
      return;
    }
    setState(() => _saving = true);
    final String? err = await OraclePersonaStore.save(c, _copy(_data));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = err != null;
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F26),
        appBar: AppBar(
          title: const Text('شخصیت اوراکل'),
          actions: <Widget>[
            IconButton(
              tooltip: _json ? 'فرم' : 'JSON (پیشرفته)',
              icon: Icon(_json ? Icons.view_list_rounded : Icons.data_object_rounded),
              onPressed: _loading ? null : _toggleJson,
            ),
            IconButton(
              tooltip: 'پیش‌فرض',
              icon: const Icon(Icons.restore_rounded),
              onPressed: () => setState(() {
                _data = _copy(kOraclePersonaDefaults);
                _c.text = const JsonEncoder.withIndent('  ').convert(_data);
                _dirty = true;
                _formKey++;
              }),
            ),
            IconButton(
              tooltip: 'ذخیره',
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.save_rounded, color: _dirty ? const Color(0xFFFFC857) : null),
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
                        'هر بخش را باز کن و ویرایش کن: بازیکن‌ها و اسم‌های دیگرشان، جمله‌ها، خوشامدها، جمله‌های خودجوش، '
                            'واکنش برد/باخت، آموزش‌ها، متن تورها، احتمال‌ها و روشن/خاموش هر بخش. {jan} = «جاااااااااان».',
                    style: const TextStyle(color: Color(0xFF8FF3FF), fontSize: 12),
                  ),
                ),
                Expanded(
                  child: _json
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: TextField(
                              controller: _c,
                              maxLines: null,
                              expands: true,
                              onChanged: (_) => _dirty = true,
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                              decoration: const InputDecoration(
                                  border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF0E1838)),
                            ),
                          ),
                        )
                      : JsonFormEditor(
                          key: ValueKey<int>(_formKey),
                          value: _data,
                          labels: kOracleConfigLabels,
                          onChanged: () {
                            if (!_dirty) setState(() => _dirty = true);
                          },
                        ),
                ),
              ]),
      ),
    );
  }
}
