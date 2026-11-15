import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import 'models/nova_models.dart';
import 'state/nova_controller.dart';
import 'ui/nova_follow.dart';
import 'ui/nova_composer.dart';
import 'ui/nova_post_card.dart';
import 'ui/nova_tabs.dart';
import 'ui/nova_visuals.dart';

/// NOVA GALLERY — the social network world (offline-first).
class NovaGalleryPage extends ConsumerStatefulWidget {
  const NovaGalleryPage({super.key});

  @override
  ConsumerState<NovaGalleryPage> createState() => _NovaGalleryPageState();
}

class _NovaGalleryPageState extends ConsumerState<NovaGalleryPage> {
  int _tab = 0;
  String _query = '';

  static const int _feed = 0;
  static const int _explore = 1;
  static const int _reels = 2;
  static const int _alerts = 3;
  static const int _profile = 4;

  void _onHashtag(String tag) {
    setState(() {
      _query = '#$tag';
      _tab = _explore;
    });
  }

  void _onMention(String name) {
    final profile = ref.read(profileProvider);
    final String mine = profile.username.trim().toLowerCase().replaceAll(' ', '_');
    if (mine.isNotEmpty && (name.toLowerCase() == mine || name.toLowerCase() == profile.username.trim().toLowerCase())) {
      setState(() => _tab = _profile);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => Padding(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            NovaAvatar(name: name, size: 48),
            const SizedBox(width: 12),
            Text('@$name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 14),
          if (ref.read(novaControllerProvider).online != null)
            NovaUserLookup(username: name)
          else
            const OnlineOnlyNotice(featureFa: 'دیدن پروفایل دیگر کاوشگران', featureEn: "Viewing other explorers' profiles"),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(c).pop();
              setState(() {
                _query = '@$name';
                _tab = _explore;
              });
            },
            icon: const Icon(Icons.search_rounded),
            label: Text(c.tx('پست‌هایی که از @$name نام برده‌اند', 'Posts mentioning @$name')),
          ),
        ]),
      ),
    );
  }

  void _openPost(String id) {
    final NovaPost? post = ref.read(novaControllerProvider).byId(id);
    if (post == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tx('این پست دیگر وجود ندارد.', 'This post no longer exists.'))));
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext c) => _NovaPostPage(postId: id, onHashtag: _onHashtag, onMention: _onMention),
    ));
  }

  Widget _body() {
    switch (_tab) {
      case _explore:
        return NovaExploreTab(
          key: const ValueKey<String>('explore'),
          query: _query,
          onQuery: (String q) => _query = q,
          onMention: _onMention,
        );
      case _reels:
        return NovaReelsTab(key: const ValueKey<String>('reels'), onHashtag: _onHashtag, onMention: _onMention);
      case _alerts:
        return NovaNotificationsTab(key: const ValueKey<String>('alerts'), onOpenPost: _openPost);
      case _profile:
        return NovaProfileTab(key: const ValueKey<String>('profile'), onOpenPost: _openPost);
      case _feed:
      default:
        return NovaFeedTab(key: const ValueKey<String>('feed'), onHashtag: _onHashtag, onMention: _onMention);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(novaControllerProvider);
    final bool reduced = ref.watch(settingsProvider).reducedMotion;
    final pal = WorldPalette.nova;
    final int unread = ctrl.unreadCount;
    return NxWorldScaffold(
      title: 'NOVA GALLERY',
      palette: pal,
      actions: <Widget>[
        IconButton(
          tooltip: context.tx('استوری تازه', 'New story'),
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: () => showStoryComposer(context),
        ),
      ],
      floatingActionButton: _tab == _alerts
          ? null
          : FloatingActionButton(
              backgroundColor: pal.primary,
              foregroundColor: NxColors.navyDeep,
              tooltip: _tab == _reels ? context.tx('پست حرکتی', 'Motion post') : context.tx('پست تازه', 'New post'),
              onPressed: () => showNovaComposer(context, motion: _tab == _reels),
              child: Icon(_tab == _reels ? Icons.movie_filter_rounded : Icons.edit_rounded),
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xEE1A0B2E),
        indicatorColor: pal.primary.withValues(alpha: 0.28),
        selectedIndex: _tab,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: <Widget>[
          NavigationDestination(
              icon: const Icon(Icons.dynamic_feed_rounded), label: context.tx('فید', 'Feed')),
          NavigationDestination(icon: const Icon(Icons.explore_rounded), label: context.tx('اکتشاف', 'Explore')),
          NavigationDestination(icon: const Icon(Icons.movie_filter_rounded), label: context.tx('ریلز', 'Reels')),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_rounded),
            ),
            label: context.tx('اعلان‌ها', 'Alerts'),
          ),
          NavigationDestination(icon: const Icon(Icons.person_rounded), label: context.tx('پروفایل', 'Profile')),
        ],
      ),
      body: AnimatedSwitcher(
        duration: reduced ? Duration.zero : NxMotion.normal,
        switchInCurve: NxMotion.curve,
        transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        child: _body(),
      ),
    );
  }
}

/// Single post page (opened from notifications or the profile grid).
class _NovaPostPage extends ConsumerWidget {
  const _NovaPostPage({required this.postId, required this.onHashtag, required this.onMention});
  final String postId;
  final ValueChanged<String> onHashtag;
  final ValueChanged<String> onMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NovaPost? post = ref.watch(novaControllerProvider).byId(postId);
    return NxWorldScaffold(
      title: 'NOVA',
      palette: WorldPalette.nova,
      showWallet: false,
      body: post == null
          ? NovaEmptyState(
              pose: 'confused',
              fa: 'این پست حذف شده است.',
              en: 'This post was deleted.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tx('بازگشت', 'Back')),
              ),
            )
          : ListView(children: <Widget>[
              NovaPostCard(
                post: post,
                onHashtag: (String t) {
                  Navigator.of(context).pop();
                  onHashtag(t);
                },
                onMention: (String m) {
                  Navigator.of(context).pop();
                  onMention(m);
                },
              ),
            ]),
    );
  }
}
