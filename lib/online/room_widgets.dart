// Room widgets shared by lobby + match — ChatPanel, VoiceBar, PingBadge (port of the RN online/ui.tsx parts).
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../i18n/i18n.dart';
import '../net/voice.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'link.dart';
import 'ui.dart';

class PingBadge extends StatelessWidget {
  final RoomLink link;
  const PingBadge({super.key, required this.link});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LinkState>(
        valueListenable: link,
        builder: (_, ls, _) {
          final r = ls.rtt;
          final col = r == null ? C.dim : r < 80 ? C.green : r < 150 ? C.gold : C.red;
          return Container(
            height: 24, padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withValues(alpha: .53)), color: rgba(6, 10, 30, .85)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 5), decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
              Text(r == null ? '— ms' : '$r ms', style: fs(F.head, 10, color: col)),
              if (link.fastReady) Padding(padding: const EdgeInsets.only(left: 4), child: Text('⚡', style: fs(F.body, 10, color: col))),
            ]),
          );
        },
      );
}

class ChatPanel extends StatefulWidget {
  final RoomLink link;
  final bool compact;
  final double height;
  const ChatPanel({super.key, required this.link, this.compact = false, this.height = 260});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final ctl = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.link.chatOpen = true;
    widget.link.markRead();
  }

  @override
  void dispose() {
    widget.link.chatOpen = false;
    super.dispose();
  }

  void send() {
    widget.link.sendChat(ctl.text);
    ctl.clear();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: widget.height,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: rgba(8, 12, 34, .94), border: Border.all(color: C.line)),
        child: Column(children: [
          Expanded(
            child: ValueListenableBuilder<LinkState>(
              valueListenable: widget.link,
              builder: (_, ls, _) => ls.chat.isEmpty
                  ? Center(child: T('هنوز پیامی نیست', style: fs(F.body, TS.small, color: C.dim)))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(S.s),
                      itemCount: ls.chat.length,
                      itemBuilder: (_, i) {
                        final c = ls.chat[ls.chat.length - 1 - i], mine = c.uid == widget.link.me;
                        return Align(
                          alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .7),
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: S.m, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: mine ? rgba(79, 227, 255, .16) : rgba(20, 30, 70, .9),
                              border: Border.all(color: mine ? rgba(79, 227, 255, .35) : C.line),
                            ),
                            child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
                              if (!mine) Text(c.name, style: fs(F.bold, TS.tiny, color: C.cyan)),
                              Text(c.text, style: fs(F.body, TS.small)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(S.s),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x2478B4FF)))),
            child: Row(children: [
              Press(
                onPress: send,
                child: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: rgba(79, 227, 255, .18), border: Border.all(color: C.cyan)),
                  child: Text('➤', style: fs(F.body, 16, color: C.cyan)),
                ),
              ),
              const SizedBox(width: S.s),
              Expanded(
                child: TextField(
                  controller: ctl,
                  maxLength: 200,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: fs(F.body, 14),
                  onSubmitted: (_) => send(),
                  decoration: InputDecoration(hintText: tr('پیام…'), counterText: '', isDense: true),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class VoiceBar extends StatelessWidget {
  final RoomLink link;
  final bool enabled, compact;
  const VoiceBar({super.key, required this.link, this.enabled = true, this.compact = false});

  Widget _btn(String label, {required VoidCallback onPress, bool on = true, Color? color}) => Padding(
        padding: const EdgeInsets.only(right: S.s),
        child: Press(
          onPress: () {
            buzz();
            onPress();
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 44), height: 44, padding: const EdgeInsets.symmetric(horizontal: 10), alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: on ? rgba(8, 14, 40, .85) : rgba(40, 40, 60, .5), border: Border.all(color: on ? (color ?? C.line) : C.dim2)),
            child: T(label, style: fs(F.bold, TS.small, color: on ? (color ?? C.text) : C.dim)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = link.voice;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: v,
      builder: (_, s, _) {
        if (!enabled) return const SizedBox.shrink();
        if (s.status == VoiceStatus.off || s.status == VoiceStatus.error) {
          return Row(mainAxisSize: MainAxisSize.min, children: [
            _btn(compact ? '🎙' : '🎙 ورود به صدا', onPress: v.join, color: C.green),
            if (s.error != null && !compact) Flexible(child: T(s.error!, n: 1, style: fs(F.body, TS.cap, color: C.red))),
          ]);
        }
        if (s.status == VoiceStatus.connecting) return _btn('…', onPress: () {});
        final talking = s.speaking.where((x) => x != link.me).length;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (s.canPublish) _btn(s.mic ? '🎙' : '🔇', on: s.mic, color: s.speaking.contains(link.me) ? C.green : C.cyan, onPress: () => v.setMic(!s.mic)),
          _btn(s.speaker ? '🔊' : '🔈', on: s.speaker, onPress: () => v.setSpeaker(!s.speaker)),
          if (!compact) _btn('خروج', color: C.red, onPress: v.leave),
          if (talking > 0) Img(UI2['c_mega'], w: 18, h: 18),
        ]);
      },
    );
  }
}
