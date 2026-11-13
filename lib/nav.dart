// App-wide navigation helpers (port of src/nav.tsx): overlays that can be opened from anywhere.
import 'package:material_ui/material_ui.dart';

enum OnlineEntry { hub, tours, ranks, arena, challenges, leagues }

class Nav {
  final void Function(String m, [String k]) toast;
  final void Function([OnlineEntry e, String? quick]) openOnline;
  final void Function(String uid) openProfile;
  final void Function(String conversationId) openChat;
  final void Function(String clubId) openClub;
  final VoidCallback openTeam;
  const Nav({required this.toast, required this.openOnline, required this.openProfile, required this.openChat, required this.openClub, required this.openTeam});
}

class NavScope extends InheritedWidget {
  final Nav nav;
  const NavScope({super.key, required this.nav, required super.child});
  static Nav of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<NavScope>()!.nav;
  @override
  bool updateShouldNotify(NavScope o) => false;
}
