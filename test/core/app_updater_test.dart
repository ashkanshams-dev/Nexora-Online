import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/update/app_updater.dart';

Map<String, dynamic> rel(String tag, String body, {bool apk = true}) => <String, dynamic>{
      'tag_name': tag,
      'body': body,
      'draft': false,
      'assets': apk
          ? <dynamic>[
              <String, dynamic>{'name': 'NEXORA-redesign-universal.apk', 'browser_download_url': 'https://x/$tag.apk', 'size': 10}
            ]
          : <dynamic>[],
    };

void main() {
  test('only redesign-* releases with a higher vc are offered, highest wins', () {
    final List<dynamic> list = <dynamic>[
      rel('v2.0.0', 'RN app latest vc=9999'),
      rel('redesign-50', 'build vc=50'),
      rel('redesign-57', 'build\nvc=57'),
      rel('redesign-60', 'no apk vc=60', apk: false),
      rel('nxg-v3', 'vc=80'),
    ];
    final AppRelease? r = AppUpdater.pickBest(list, 49);
    expect(r?.vc, 57);
    expect(r?.tag, 'redesign-57');
    expect(AppUpdater.pickBest(list, 57), isNull);
  });

  test('full (non-prerelease) redesign releases count too; notes are cleaned', () {
    final Map<String, dynamic> full = rel('redesign-70', '<p align="center"><img src="x"/></p>\n## ✨ Hi\n\n\n\n- one\n<sub>vc=70 · abc</sub>');
    full['prerelease'] = false;
    final AppRelease? r = AppUpdater.pickBest(<dynamic>[full, rel('redesign-65', 'vc=65')], 60);
    expect(r?.vc, 70);
    expect(r?.notes, '## ✨ Hi\n\n- one');
  });
}
