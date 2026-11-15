import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/online/netcode.dart';

void main() {
  test('v4 peers only -> compatible', () {
    expect(protoCheck(me: 'a', online: {'a': (true, kProtoVersion), 'b': (true, kProtoVersion)}), isNull);
  });
  test('v3 Flutter peer (no pv) -> they must update', () {
    expect(protoCheck(me: 'a', online: {'a': (true, kProtoVersion), 'b': (true, null)}), kMsgUpdateThem);
  });
  test('v0.5 peer (pv 4, old physics) -> they must update', () {
    expect(protoCheck(me: 'a', online: {'a': (true, kProtoVersion), 'b': (true, 4)}), kMsgUpdateThem);
  });
  test('newer peer -> I must update', () {
    expect(protoCheck(me: 'a', online: {'a': (true, kProtoVersion), 'b': (true, kProtoVersion + 1)}), kMsgUpdateMe);
  });
  test('RN/Godot peer (no c:fl) keeps the legacy classic path', () {
    expect(protoCheck(me: 'a', online: {'b': (false, null)}), isNull);
  });
  test('host snapshot check', () {
    expect(snapProtoCheck({'pf': 'stars', 'pv': kProtoVersion}), isNull);
    expect(snapProtoCheck({'pf': 'stars'}), kMsgUpdateThem); // v3 Flutter host
    expect(snapProtoCheck({'pf': 'stars', 'pv': kProtoVersion + 1}), kMsgUpdateMe);
    expect(snapProtoCheck({'pf': 'stars', 'pv': 8}), kMsgUpdateThem); // v0.7 host (no s.fb pitch/ball sync)
    expect(snapProtoCheck({'pf': 'stars', 'pv': 4}), kMsgUpdateThem); // v0.5 host (old physics)
    expect(snapProtoCheck({'q': 1}), isNull); // RN host
  });
}
