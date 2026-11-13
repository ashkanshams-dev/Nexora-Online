// Small shared helpers for the social screens (port of the exports of src/social/Social.tsx).
import '../ui/theme.dart';

const KIND_LABEL = {'dm': 'گفتگو', 'group': 'گروه', 'channel': 'کانال', 'club': 'باشگاه'};

DateTime? _dt(Object? iso) => iso == null ? null : DateTime.tryParse('$iso');

/// online = seen in the last 3 minutes
bool isOnline(Object? at) {
  final d = _dt(at);
  return d != null && DateTime.now().difference(d).inSeconds < 180;
}

String timeAgo(Object? iso) {
  final d = _dt(iso);
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  return s < 60
      ? 'الان'
      : s < 3600
          ? '${fa(s ~/ 60)} دقیقه'
          : s < 86400
              ? '${fa(s ~/ 3600)} ساعت'
              : '${fa(s ~/ 86400)} روز';
}
