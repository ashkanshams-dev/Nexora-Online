// Voice chat over LiveKit — port of src/net/voice.ts. Same `livekit-token` edge function and room naming
// (the function decides room/permissions from {room_id}); one session per room; never throws to callers.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

({bool ok, String? reason}) voiceSupport() {
  if (kIsWeb) return (ok: false, reason: 'چت صوتی فقط روی موبایل');
  return (ok: true, reason: null);
}

enum VoiceStatus { off, connecting, on, error }

class VoiceState {
  final VoiceStatus status;
  final bool mic, speaker, canPublish;
  final List<String> speaking;
  final String? error;
  const VoiceState({this.status = VoiceStatus.off, this.mic = false, this.speaker = true, this.canPublish = false, this.speaking = const [], this.error});
  VoiceState copy({VoiceStatus? status, bool? mic, bool? speaker, bool? canPublish, List<String>? speaking, String? error, bool clearError = false}) => VoiceState(
      status: status ?? this.status, mic: mic ?? this.mic, speaker: speaker ?? this.speaker, canPublish: canPublish ?? this.canPublish,
      speaking: speaking ?? this.speaking, error: clearError ? null : error ?? this.error);
}

/// lowers game audio while voice is live (port of setVoiceActive in sound.ts)
final ValueNotifier<int> voiceActiveCount = ValueNotifier(0);

class Voice extends ValueNotifier<VoiceState> {
  final String roomId;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _ev;
  bool _alive = true, _counted = false;
  Voice(this.roomId) : super(const VoiceState());

  void _set(VoiceState s) {
    value = s;
    final active = s.status == VoiceStatus.on || s.mic;
    if (active != _counted) {
      _counted = active;
      voiceActiveCount.value += active ? 1 : -1;
    }
  }

  Future<void> join() async {
    final sup = voiceSupport();
    if (!sup.ok) return _set(value.copy(status: VoiceStatus.error, error: sup.reason));
    if (value.status == VoiceStatus.connecting || value.status == VoiceStatus.on) return;
    _set(value.copy(status: VoiceStatus.connecting, clearError: true));
    try {
      Map<String, dynamic> data;
      try {
        final r = await supabase.functions.invoke('livekit-token', body: {'room_id': roomId});
        data = Map<String, dynamic>.from(r.data as Map);
      } on FunctionException catch (e) {
        final body = e.details;
        if (e.status == 503 || (body is Map && body['error'] == 'voice_not_configured')) throw Exception('چت صوتی هنوز فعال نشده');
        if (e.status == 403) throw Exception('برای چت صوتی باید داخل اتاق باشی');
        throw Exception('اتصال به سرور صدا ناموفق بود');
      }
      if (!_alive) return;
      var canPublish = data['canPublish'] == true;
      if (canPublish && Platform.isAndroid) {
        final g = await Permission.microphone.request();
        if (!g.isGranted) canPublish = false;
      }
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false));
      _room = room;
      _ev = room.createListener()
        ..on<lk.ActiveSpeakersChangedEvent>((e) => _set(value.copy(speaking: e.speakers.map((p) => p.identity).toList())))
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (_alive) _set(value.copy(status: VoiceStatus.off, mic: false, speaking: const []));
        })
        ..on<lk.TrackSubscribedEvent>((e) {
          if (!value.speaker) e.publication.disable();
        });
      await room.connect(data['url'] as String, data['token'] as String, connectOptions: const lk.ConnectOptions(autoSubscribe: true));
      if (!_alive) {
        await room.disconnect();
        return;
      }
      _set(value.copy(status: VoiceStatus.on, canPublish: canPublish, mic: false));
      if (canPublish) await setMic(true);
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      _set(value.copy(status: VoiceStatus.error, error: RegExp(r'[\u0600-\u06FF]').hasMatch(m) ? m : 'اتصال صدا ناموفق بود'));
      leave(keepError: true);
    }
  }

  Future<void> setMic(bool on) async {
    final r = _room;
    if (r == null || !value.canPublish) return;
    try {
      await r.localParticipant?.setMicrophoneEnabled(on);
      _set(value.copy(mic: on));
    } catch (_) {
      _set(value.copy(mic: false));
    }
  }

  void setSpeaker(bool on) {
    _set(value.copy(speaker: on));
    try {
      for (final p in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
        for (final pub in p.audioTrackPublications) {
          on ? pub.enable() : pub.disable();
        }
      }
    } catch (_) {}
  }

  void leave({bool keepError = false}) {
    final r = _room;
    _room = null;
    _ev?.dispose();
    _ev = null;
    try {
      r?.disconnect();
    } catch (_) {}
    if (!keepError) _set(value.copy(status: VoiceStatus.off, mic: false, speaking: const []));
  }

  void destroy() {
    _alive = false;
    leave();
    if (_counted) {
      _counted = false;
      voiceActiveCount.value -= 1;
    }
  }
}
