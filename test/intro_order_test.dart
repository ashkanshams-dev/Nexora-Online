// v0.6.1: the launch intro plays the owner's clips in order intro1 -> intro2 -> intro3, then finishes (fake player).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/intro/video_intro.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FakePlayer extends VideoPlayerPlatform {
  final assets = <int, String>{};
  final played = <String>[];
  final _ev = <int, StreamController<VideoEvent>>{};
  var _n = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource d) async {
    final id = _n++;
    assets[id] = d.asset ?? '?';
    _ev[id] = StreamController<VideoEvent>();
    scheduleMicrotask(() => _ev[id]!.add(VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(seconds: 1), size: const Size(720, 720))));
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions o) => create(o.dataSource);
  @override
  Stream<VideoEvent> videoEventsFor(int id) => _ev[id]!.stream;
  @override
  Future<void> play(int id) async {
    played.add(assets[id]!);
    Timer(const Duration(milliseconds: 1000), () => _ev[id]!.add(VideoEvent(eventType: VideoEventType.completed)));
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setLooping(int id, bool l) async {}
  @override
  Future<void> setVolume(int id, double v) async {}
  @override
  Future<void> seekTo(int id, Duration p) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double s) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> dispose(int id) async {}
  @override
  Future<void> setMixWithOthers(bool m) async {}
  @override
  Widget buildView(int id) => const SizedBox();
  @override
  Widget buildViewWithOptions(VideoViewOptions o) => const SizedBox();
}

void main() {
  testWidgets('intro clips play in order 1 -> 2 -> 3 then finish', (t) async {
    final fake = _FakePlayer();
    VideoPlayerPlatform.instance = fake;
    var done = false, failed = false;
    await t.pumpWidget(MaterialApp(home: VideoIntro(onDone: () => done = true, onFail: () => failed = true)));
    for (var i = 0; i < 60 && !done && !failed; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(failed, isFalse);
    expect(fake.played, ['assets/video/intro1.mp4', 'assets/video/intro2.mp4', 'assets/video/intro3.mp4']);
    expect(done, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });
}
