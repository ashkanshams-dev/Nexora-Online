import 'package:flutter/material.dart';

/// A form for a JSON document (maps, lists, strings, numbers, booleans) — used for the ORACLE personality config so
/// admins edit fields, lists and switches instead of raw JSON. The value is edited in place; [onChanged] fires on
/// every edit. Known keys get Persian labels; unknown keys show their key.
class JsonFormEditor extends StatefulWidget {
  const JsonFormEditor({required this.value, required this.onChanged, this.labels = const <String, String>{}, super.key});

  final Map<String, dynamic> value;
  final VoidCallback onChanged;
  final Map<String, String> labels;

  @override
  State<JsonFormEditor> createState() => _JsonFormEditorState();
}

class _JsonFormEditorState extends State<JsonFormEditor> {
  String _label(String k) => widget.labels[k] ?? k;

  void _changed() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<String> keys = widget.value.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
      itemCount: keys.length,
      itemBuilder: (BuildContext context, int i) {
        final String k = keys[i];
        return _field(widget.value, k, widget.value[k], depth: 0);
      },
    );
  }

  /// [parent] is a Map<String, dynamic> (key = String) or a List (key = int).
  Widget _field(Object parent, Object key, Object? v, {required int depth}) {
    final String label = key is String ? _label(key) : '#${(key as int) + 1}';
    void set(Object? nv) {
      if (parent is Map<String, dynamic>) {
        parent[key as String] = nv;
      } else if (parent is List) {
        parent[key as int] = nv;
      }
      _changed();
    }

    if (v is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8.0 + depth * 4),
        title: Text(label),
        value: v,
        onChanged: (bool b) => set(b),
      );
    }
    if (v is num) {
      final bool isProb = v is double && v >= 0 && v <= 1;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0 + depth * 4, vertical: 2),
        child: isProb
            ? Row(children: <Widget>[
                Expanded(child: Text(label)),
                SizedBox(
                  width: 170,
                  child: Slider(value: v.toDouble(), divisions: 20, label: '${(v * 100).round()}%', onChanged: (double d) => set(double.parse(d.toStringAsFixed(2)))),
                ),
                SizedBox(width: 44, child: Text('${(v * 100).round()}%')),
              ])
            : Row(children: <Widget>[
                Expanded(child: Text(label)),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    key: ValueKey<String>('n:$label:${identityHashCode(parent)}'),
                    initialValue: '$v',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (String s) {
                      final num? n = v is int ? int.tryParse(s.trim()) : double.tryParse(s.trim());
                      if (n != null) {
                        if (parent is Map<String, dynamic>) {
                          parent[key as String] = n;
                        } else if (parent is List) {
                          parent[key as int] = n;
                        }
                        widget.onChanged();
                      }
                    },
                  ),
                ),
              ]),
      );
    }
    if (v is String) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0 + depth * 4, vertical: 4),
        child: TextFormField(
          key: ValueKey<String>('s:$label:${identityHashCode(parent)}:$key'),
          initialValue: v,
          minLines: 1,
          maxLines: v.length > 40 || v.contains('\n') ? 6 : 1,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: (String s) {
            if (parent is Map<String, dynamic>) {
              parent[key as String] = s;
            } else if (parent is List) {
              parent[key as int] = s;
            }
            widget.onChanged();
          },
        ),
      );
    }
    if (v is Map) {
      final Map<String, dynamic> m = v is Map<String, dynamic> ? v : Map<String, dynamic>.from(v);
      if (!identical(m, v)) set(m);
      final String title = m['name'] is String ? '${m['name']}' : (m['id'] is String ? '${m['id']}' : label);
      return Card(
        color: Color.lerp(const Color(0xFF101A40), const Color(0xFF1A2558), depth / 4),
        margin: EdgeInsets.symmetric(horizontal: 4.0 + depth * 2, vertical: 4),
        child: ExpansionTile(
          title: Text(key is int ? title : label, style: const TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: <Widget>[for (final String k in m.keys.toList()) _field(m, k, m[k], depth: depth + 1)],
        ),
      );
    }
    if (v is List) {
      final List<dynamic> l = v;
      final bool strings = l.every((dynamic e) => e is String);
      return Card(
        color: Color.lerp(const Color(0xFF101A40), const Color(0xFF1A2558), depth / 4),
        margin: EdgeInsets.symmetric(horizontal: 4.0 + depth * 2, vertical: 4),
        child: ExpansionTile(
          title: Text('$label (${l.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: <Widget>[
            for (int i = 0; i < l.length; i++)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Expanded(child: _field(l, i, l[i], depth: depth + 1)),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFFF5A6E)),
                  onPressed: () {
                    l.removeAt(i);
                    _changed();
                  },
                ),
              ]),
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('افزودن'),
              onPressed: () {
                l.add(strings || l.isEmpty ? '' : _blank(l.first));
                _changed();
              },
            ),
          ],
        ),
      );
    }
    return ListTile(dense: true, title: Text(label), subtitle: Text('$v'));
  }

  /// Same shape as [template] with empty values (new list item).
  static Object? _blank(Object? template) {
    if (template is Map) {
      return <String, dynamic>{for (final MapEntry<dynamic, dynamic> e in template.entries) '${e.key}': _blank(e.value)};
    }
    if (template is List) return <dynamic>[];
    if (template is String) return '';
    if (template is bool) return false;
    if (template is int) return 0;
    if (template is double) return 0.0;
    return null;
  }
}

/// Persian labels for the ORACLE persona config keys.
const Map<String, String> kOracleConfigLabels = <String, String>{
  'version': 'نسخه',
  'enabled': 'روشن/خاموش بخش‌ها',
  'players': 'بازیکن‌ها',
  'greetings': 'خوشامد ورود',
  'spontaneous': 'جمله‌های خودجوش',
  'results': 'واکنش برد/باخت',
  'tutorials': 'آموزش‌ها',
  'jan': '«جاااان»',
  'tour': 'تور راهنما',
  'tours': 'متن تورها',
  'freq': 'احتمال‌ها و فاصله‌ها',
  'login_greeting_chance': 'احتمال خوشامد ورود',
  'login_original_joke_chance': 'احتمال شوخی «اورجینالی؟»',
  'spontaneous_global_gap_sec': 'حداقل فاصله‌ی جمله‌های خودجوش (ثانیه)',
  'spontaneous_category_gap_sec': 'حداقل فاصله‌ی هر دسته (ثانیه)',
  'spontaneous_chance': 'احتمال جمله‌ی خودجوش',
  'jan_chance': 'احتمال «جاااان»',
  'tutorial_auto_views': 'دفعات نمایش خودکار آموزش',
  'result_chance': 'احتمال واکنش به نتیجه',
  'margin_big': 'اختلاف برد/باخت سنگین',
  'jan_stretch': 'کشیدگی «جاااان»',
  'min': 'حداقل',
  'max': 'حداکثر',
  'base': 'پیش‌فرض',
  'unknown_player': 'جواب بازیکن ناشناس',
  'ambiguous_player': 'جواب اسم مشترک',
  'jan_wait': 'جواب «جاااان؟»',
  'id': 'شناسه',
  'name': 'نام',
  'fixed': 'جمله‌ی ثابت (عین متن)',
  'aliases': 'اسم‌های دیگر / غلط‌های تایپی',
  'lines': 'جمله‌ها',
  'traits': 'ویژگی‌ها',
  'login_greetings': 'خوشامدهای ورود',
  'login_self_original': 'خوشامد وقتی خود اورجینال وارد می‌شود',
  'login_plain': 'خوشامد ساده',
  'jan_replies': 'جواب‌های «جاااان»',
  'wake_words': 'کلمه‌های صدا زدن',
  'win': 'برد',
  'lose': 'باخت',
  'big_win': 'برد سنگین',
  'big_lose': 'باخت سنگین',
  'draw': 'مساوی',
};
