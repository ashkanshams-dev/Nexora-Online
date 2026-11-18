import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/backend/backend_gateway.dart';
import '../../../core/backend/supabase_backend.dart';
import '../../../core/online/online_config.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../data/supabase_orbit_repository.dart';
import '../models/orbit_call_state.dart';
import '../state/orbit_controller.dart';

/// Real voice / video call for an Orbit Network chat through LiveKit.
///
/// The token comes from the `nx-call-token` Edge Function, which only answers authenticated members of the chat.
/// [startNew] = this phone starts the call (rings the other members through nx_calls + a call message);
/// otherwise it joins the call already running in that chat.
class OrbitCallPage extends ConsumerStatefulWidget {
  const OrbitCallPage({
    super.key,
    required this.chatId,
    required this.title,
    this.video = false,
    this.startNew = true,
    this.callId,
  });

  final String chatId;
  final String title;
  final bool video;
  final bool startNew;
  final String? callId;

  @override
  ConsumerState<OrbitCallPage> createState() => _OrbitCallPageState();
}

class _OrbitCallPageState extends ConsumerState<OrbitCallPage> {
  Room? _room;
  EventsListener<RoomEvent>? _events;
  String? _callId;
  String? _error;
  bool _connecting = true;
  bool _mic = true;
  late bool _cam = widget.video;
  bool _speaker = true;
  bool _canPublish = true;
  DateTime? _since;
  Timer? _tick;
  bool _hadPeer = false;
  bool _ending = false;
  bool _micError = false;
  int _reconnects = 0;
  OrbitCallConnection _connection = OrbitCallConnection.connecting;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId;
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!mounted || _ending) return;
    setState(() {
      _connecting = true;
      _connection = OrbitCallConnection.connecting;
      _error = null;
      _micError = false;
    });
    final BackendGateway be = ref.read(backendProvider);
    final SupabaseOrbitRepository? repo =
        ref.read(orbitControllerProvider).online;
    if (be is! SupabaseBackend || repo == null) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connection = OrbitCallConnection.failed;
        _error = 'offline';
      });
      return;
    }
    try {
      // A manual retry must rejoin the existing call instead of creating a
      // second call row and ringing everyone again.
      if (widget.startNew && _callId == null) {
        _callId = await repo.startCall(widget.chatId, video: widget.video);
      }
      final Map<String, dynamic>? grant =
          await be.liveKitGrant(widget.chatId, video: widget.video);
      final String? token = grant?['token'] as String?;
      if (token == null) throw StateError('${grant?['error'] ?? 'no_token'}');
      _canPublish = grant?['canPublish'] != false;

      final Room room = Room(
          roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      room.addListener(_onRoom);
      final EventsListener<RoomEvent> events = room.createListener();
      _events = events;
      events.on<RoomReconnectingEvent>((_) {
        if (!mounted || _ending) return;
        setState(() {
          _connection = OrbitCallConnection.reconnecting;
          _reconnects++;
        });
      });
      events.on<RoomReconnectedEvent>((_) {
        if (!mounted || _ending) return;
        setState(() {
          _connection = OrbitCallConnection.connected;
          _connecting = false;
        });
      });
      events.on<RoomDisconnectedEvent>((_) {
        if (!mounted || _ending) return;
        setState(() {
          _connection = OrbitCallConnection.disconnected;
          _connecting = false;
        });
      });
      _room = room;
      await room.connect('${grant['url'] ?? OnlineConfig.liveKitUrl}', token);
      if (_canPublish) {
        try {
          await room.localParticipant?.setMicrophoneEnabled(true);
        } catch (_) {
          _mic = false;
          _micError = true;
        }
        if (widget.video) {
          try {
            await room.localParticipant?.setCameraEnabled(true);
          } catch (_) {
            _cam = false;
          }
        }
      } else {
        _mic = false;
        _cam = false;
      }
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (_) {}
      _since ??= DateTime.now();
      _connection = OrbitCallConnection.connected;
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = null;
        });
      }
    } catch (e) {
      await _disposeRoom();
      if (mounted) {
        setState(() {
          _connecting = false;
          _connection = OrbitCallConnection.failed;
          _error = '$e';
        });
      }
    }
  }

  void _onRoom() {
    final Room? r = _room;
    if (r == null || !mounted) return;
    if (r.remoteParticipants.isNotEmpty) _hadPeer = true;
    setState(() {});
  }

  Future<void> _disposeRoom() async {
    final Room? r = _room;
    _room = null;
    r?.removeListener(_onRoom);
    final EventsListener<RoomEvent>? events = _events;
    _events = null;
    try {
      await events?.dispose();
    } catch (_) {}
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    _ending = true;
    final Room? r = _room;
    final bool alone = r == null || r.remoteParticipants.isEmpty;
    await _disposeRoom();
    final String? id = _callId;
    final SupabaseOrbitRepository? repo =
        ref.read(orbitControllerProvider).online;
    if (id != null && alone && repo != null) await repo.endCall(id);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _retry() async {
    if (_ending || _connecting) return;
    await _disposeRoom();
    if (mounted) await _start();
  }

  @override
  void dispose() {
    _ending = true;
    _tick?.cancel();
    unawaited(_disposeRoom());
    super.dispose();
  }

  String _duration() {
    final DateTime? s = _since;
    if (s == null) return '';
    final Duration d = DateTime.now().difference(s);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Widget _tile(Participant p, {required bool local}) {
    final NxThemeColors visual = NxThemeColors.of(context);
    VideoTrack? video;
    for (final TrackPublication<Track> pub in p.videoTrackPublications) {
      final Track? t = pub.track;
      if (t is VideoTrack && !pub.muted) video = t;
    }
    final bool speaking = p.isSpeaking;
    final String name =
        local ? context.tx('تو', 'You') : (p.name.isEmpty ? 'Pilot' : p.name);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: visual.surfaceRaised,
        borderRadius: BorderRadius.circular(NxRadius.lg),
        border: Border.all(
          color: speaking ? visual.accent : visual.border.withValues(alpha: 0.65),
          width: speaking ? 3 : 1,
        ),
        boxShadow: speaking
            ? <BoxShadow>[BoxShadow(color: visual.accent.withValues(alpha: 0.4), blurRadius: 18)]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: <Widget>[
        if (video != null)
          VideoTrackRenderer(video)
        else
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: visual.accent.withValues(alpha: 0.28),
              child: Text(name.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        PositionedDirectional(
          start: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (p.isMuted) const Icon(Icons.mic_off_rounded, size: 14, color: NxColors.danger),
              const SizedBox(width: 4),
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback? onTap,
          {Color? color, bool active = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Tooltip(
          message: tip,
          child: RawMaterialButton(
            onPressed: onTap,
            shape: const CircleBorder(),
            fillColor: color ?? (active ? Colors.white.withValues(alpha: 0.16) : Colors.white),
            constraints: const BoxConstraints.tightFor(width: 58, height: 58),
            child: Icon(icon, color: color != null ? Colors.white : (active ? Colors.white : NxColors.navyDeep)),
          ),
        ),
      );

  String _statusText() {
    if (_error == 'offline') return context.tx('برای تماس باید آنلاین باشی.', 'You need to be online to call.');
    if (_connection == OrbitCallConnection.reconnecting) {
      return context.tx('اتصال قطع شد؛ تلاش برای اتصال مجدد…', 'Connection lost; reconnecting…');
    }
    if (_connection == OrbitCallConnection.disconnected) {
      return context.tx('اتصال برقرار نشد.', 'Disconnected.');
    }
    if (_connecting) return context.tx('در حال اتصال…', 'Connecting…');
    final int remotes = _room?.remoteParticipants.length ?? 0;
    if (remotes == 0) {
      return _hadPeer ? context.tx('بقیه رفتند', 'Everyone else left') : context.tx('در حال زنگ زدن…', 'Ringing…');
    }
    return _duration();
  }

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Room? room = _room;
    final List<Widget> tiles = <Widget>[];
    if (room != null && !_connecting && _error == null) {
      final LocalParticipant? lp = room.localParticipant;
      if (lp != null) tiles.add(_tile(lp, local: true));
      for (final RemoteParticipant rp in room.remoteParticipants.values) {
        tiles.add(_tile(rp, local: false));
      }
    }
    final bool canRetry = _connection == OrbitCallConnection.disconnected || _connection == OrbitCallConnection.failed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool did, Object? _) {
        if (!did) unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: visual.background,
        body: NxBrandBackground(
          child: SafeArea(
            child: Column(children: <Widget>[
              const SizedBox(height: 12),
              Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('${widget.video ? context.tx('تماس تصویری', 'Video call') : context.tx('تماس صوتی', 'Voice call')} · ${_statusText()}',
                  style: const TextStyle(color: NxColors.textDim)),
              if (_reconnects > 0 && _connection == OrbitCallConnection.connected)
                Text(context.tx('اتصال مجدد شد', 'Reconnected'), style: TextStyle(color: visual.accent, fontSize: 11)),
              if (_micError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(context.tx('دسترسی میکروفون برقرار نشد؛ تماس فقط شنیداری است.', 'Microphone access failed; you are listening only.'),
                      textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontSize: 12)),
                ),
              if (_error != null && _error != 'offline')
                Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontSize: 12))),
              if (canRetry)
                TextButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded), label: Text(context.tx('تلاش دوباره', 'Retry'))),
              const SizedBox(height: 8),
              Expanded(
                child: tiles.isEmpty
                    ? Center(child: _connecting ? CircularProgressIndicator(color: visual.accent) : Icon(widget.video ? Icons.videocam_off_rounded : Icons.call_end_rounded, size: 64, color: NxColors.textDim))
                    : GridView.count(padding: const EdgeInsets.all(12), crossAxisCount: tiles.length <= 2 ? 1 : 2, childAspectRatio: tiles.length <= 2 ? 1.5 : 0.9, mainAxisSpacing: 10, crossAxisSpacing: 10, children: tiles),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                  if (_canPublish && _error == null)
                    _btn(_mic ? Icons.mic_rounded : Icons.mic_off_rounded, context.tx('میکروفون', 'Microphone'), () async {
                      final bool next = !_mic;
                      try {
                        await room?.localParticipant?.setMicrophoneEnabled(next);
                        _mic = next;
                        _micError = false;
                      } catch (_) {
                        _micError = true;
                      }
                      if (mounted) setState(() {});
                    }, active: _mic),
                  if (_canPublish && _error == null)
                    _btn(_cam ? Icons.videocam_rounded : Icons.videocam_off_rounded, context.tx('دوربین', 'Camera'), () async {
                      final bool next = !_cam;
                      try {
                        await room?.localParticipant?.setCameraEnabled(next);
                        _cam = next;
                      } catch (_) {}
                      if (mounted) setState(() {});
                    }, active: _cam),
                  if (_error == null)
                    _btn(_speaker ? Icons.volume_up_rounded : Icons.hearing_rounded, context.tx('بلندگو', 'Speaker'), () async {
                      _speaker = !_speaker;
                      try { await Hardware.instance.setSpeakerphoneOn(_speaker); } catch (_) {}
                      if (mounted) setState(() {});
                    }, active: _speaker),
                  _btn(Icons.call_end_rounded, context.tx('قطع', 'Hang up'), _hangUp, color: NxColors.danger),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
