import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/online/online_service.dart';
import '../data/social_profile_repository.dart';

class SocialProfilePage extends ConsumerStatefulWidget {
  const SocialProfilePage({super.key, this.userId});
  final String? userId;
  @override ConsumerState<SocialProfilePage> createState() => _SocialProfilePageState();
}

class _SocialProfilePageState extends ConsumerState<SocialProfilePage> {
  SocialProfileRepository? _repo;
  SocialProfile? _profile;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool get _mine => widget.userId == null || widget.userId == _repo?.me;

  @override
  void initState() { super.initState(); unawaited(_load()); }

  Future<void> _load() async {
    final online = ref.read(onlineProvider);
    final c = online.client;
    if (c == null || online.user == null) {
      if (mounted) setState(() { _loading = false; _error = 'ورود واقعی لازم است'; });
      return;
    }
    _repo = SocialProfileRepository(c);
    try {
      final p = await _repo!.profile(widget.userId ?? _repo!.me);
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'دریافت پروفایل ناموفق بود'; });
    }
  }

  Future<void> _toggleFollow() async {
    final p = _profile;
    final r = _repo;
    if (p == null || r == null || _busy) return;
    setState(() { _busy = true; });
    try {
      final next = await r.toggleFollow(p.id, follow: !p.isFollowing && !p.isPending);
      if (mounted) setState(() { _profile = next; _busy = false; });
    } catch (_) {
      if (mounted) { setState(() { _busy = false; }); _snack('عملیات Follow ناموفق بود'); }
    }
  }

  Future<void> _avatar() async {
    final r = _repo;
    if (r == null || _busy) return;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 768, maxHeight: 768, imageQuality: 84);
    if (f == null) return;
    setState(() { _busy = true; });
    try {
      final p = await r.uploadAvatar(f);
      if (mounted) setState(() { _profile = p; _busy = false; });
    } catch (_) {
      if (mounted) { setState(() { _busy = false; }); _snack('آپلود تصویر ناموفق بود'); }
    }
  }

  Future<void> _edit() async {
    final p = _profile;
    final r = _repo;
    if (p == null || r == null) return;
    final name = TextEditingController(text: p.displayName);
    final user = TextEditingController(text: p.username);
    final bio = TextEditingController(text: p.bio);
    final web = TextEditingController(text: p.website);
    final loc = TextEditingController(text: p.location);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('ویرایش پروفایل'),
      content: SingleChildScrollView(child: Column(children: <Widget>[
        TextField(controller: user, decoration: const InputDecoration(labelText: 'username')),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'نام نمایشی')),
        TextField(controller: bio, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio')),
        TextField(controller: web, decoration: const InputDecoration(labelText: 'Website')),
        TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
      ])),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ذخیره')),
      ],
    ));
    if (ok != true) return;
    setState(() { _busy = true; });
    try {
      final next = await r.updateProfile(username: user.text, displayName: name.text, bio: bio.text, website: web.text, location: loc.text, avatarUrl: p.avatarUrl);
      if (mounted) setState(() { _profile = next; _busy = false; });
    } catch (_) {
      if (mounted) { setState(() { _busy = false; }); _snack('ذخیره پروفایل ناموفق بود'); }
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Profile' : '@${p.username}'), actions: <Widget>[
        if (_mine && p != null) IconButton(onPressed: _edit, icon: const Icon(Icons.edit_rounded)),
      ]),
      body: p == null ? Center(child: Text(_error ?? 'خطا')) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            _avatarView(p, 92), const SizedBox(width: 18), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(p.displayName.isEmpty ? p.username : p.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('@${p.username}'), const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[_stat('Posts', p.posts), _stat('Followers', p.followers), _stat('Following', p.following)]),
            ])),
          ]),
          if (p.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 18), child: Text(p.bio)),
          if (p.location.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.location_on_outlined), title: Text(p.location)),
          if (p.website.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(p.website)),
          const SizedBox(height: 12),
          if (!_mine) Row(children: <Widget>[
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _toggleFollow, icon: Icon(p.isPending ? Icons.hourglass_top_rounded : p.isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded), label: Text(p.isPending ? 'Pending' : p.isFollowing ? 'Following' : 'Follow'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: _busy ? null : () async {
              final id = await _repo!.openDirect(p.id);
              if (!mounted) return;
              await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => SocialChatPage(repo: _repo!, chatId: id, peer: p)));
            }, icon: const Icon(Icons.message_rounded), label: const Text('Message'))),
          ]),
          if (_mine) OutlinedButton.icon(onPressed: _busy ? null : _avatar, icon: const Icon(Icons.photo_camera_rounded), label: const Text('تغییر عکس پروفایل')),
          if (_mine && p.avatarUrl != null) TextButton(onPressed: _busy ? null : () async {
            setState(() { _busy = true; });
            final next = await _repo!.deleteAvatar();
            if (mounted) setState(() { _profile = next; _busy = false; });
          }, child: const Text('حذف عکس')),
        ]),
      ),
    );
  }

  Widget _avatarView(SocialProfile p, double size) => ClipOval(child: p.avatarUrl == null
      ? Container(width: size, height: size, color: Colors.blueGrey, child: Icon(Icons.person, size: size * .55))
      : Image.network(p.avatarUrl!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: size, height: size, color: Colors.blueGrey, child: const Icon(Icons.person))));
  Widget _stat(String label, int value) => Column(children: <Widget>[Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, style: const TextStyle(fontSize: 12))]);
}

class SocialChatPage extends StatefulWidget {
  const SocialChatPage({super.key, required this.repo, required this.chatId, required this.peer});
  final SocialProfileRepository repo;
  final String chatId;
  final SocialProfile peer;
  @override State<SocialChatPage> createState() => _SocialChatPageState();
}

class _SocialChatPageState extends State<SocialChatPage> {
  final TextEditingController _text = TextEditingController();
  late final Stream<List<SocialMessage>> _stream;
  @override void initState() { super.initState(); _stream = widget.repo.messageStream(widget.chatId); }
  @override void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    try { await widget.repo.sendMessage(widget.chatId, text); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ارسال پیام ناموفق بود'))); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Row(children: <Widget>[
      ClipOval(child: widget.peer.avatarUrl == null ? const Icon(Icons.person) : Image.network(widget.peer.avatarUrl!, width: 34, height: 34, fit: BoxFit.cover)),
      const SizedBox(width: 8), Text('@${widget.peer.username}'),
    ])),
    body: Column(children: <Widget>[
      Expanded(child: StreamBuilder<List<SocialMessage>>(stream: _stream, builder: (c, snapshot) {
        final list = snapshot.data ?? const <SocialMessage>[];
        if (list.isEmpty) return const Center(child: Text('هنوز پیامی نیست'));
        return ListView.builder(padding: const EdgeInsets.all(16), itemCount: list.length, itemBuilder: (_, i) => Align(
          alignment: list[i].author == widget.repo.me ? Alignment.centerRight : Alignment.centerLeft,
          child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(list[i].text))),
        ));
      })),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: <Widget>[
        Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'پیام…'))),
        IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
      ]))),
    ]),
  );
}
