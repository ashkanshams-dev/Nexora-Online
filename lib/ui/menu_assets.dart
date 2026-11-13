// Menu art (assets/g/menu, unchanged files) — port of src/ui/menuAssets.ts
String menu(String k) => 'assets/g/menu/$k.webp';

class MENU {
  static final ic_settings = menu('ic_settings'), ic_home = menu('ic_home'), ic_trophy = menu('ic_trophy'), ic_shop = menu('ic_shop');
  static final ic_gift = menu('ic_gift'), ic_play = menu('ic_play'), ic_pause = menu('ic_pause'), ic_music = menu('ic_music');
  static final ic_sound = menu('ic_sound'), ic_mute = menu('ic_mute'), ic_info = menu('ic_info'), ic_help = menu('ic_help');
  static final ic_exit = menu('ic_exit'), ic_mail = menu('ic_mail'), ic_bell = menu('ic_bell'), ic_friends = menu('ic_friends'), ic_plus = menu('ic_plus');
  static final g_coin = menu('g_coin'), g_gem = menu('g_gem'), g_xp = menu('g_xp'), g_crown = menu('g_crown'), g_star = menu('g_star');
  static final g_check = menu('g_check'), g_x = menu('g_x'), g_plus = menu('g_plus'), g_mail = menu('g_mail'), g_friends = menu('g_friends');
  static final g_addfriend = menu('g_addfriend'), g_block = menu('g_block'), g_chevrons = menu('g_chevrons'), g_ticket = menu('g_ticket');
  static final g_ticket_gold = menu('g_ticket_gold'), g_signal = menu('g_signal');
  static final rank_bronze = menu('rank_bronze'), rank_silver = menu('rank_silver'), rank_gold = menu('rank_gold'), rank_epic = menu('rank_epic');
  static final shield_crown = menu('shield_crown'), shield_star = menu('shield_star'), shield_gem = menu('shield_gem');
  static final logo = menu('logo'), title_banner = menu('title_banner'), vs_card = menu('vs_card');
  static final banner_victory = menu('banner_victory'), banner_defeat = menu('banner_defeat'), banner_draw = menu('banner_draw'), banner_goal = menu('banner_goal');
  static final frame_panel = menu('frame_panel'), frame_wide = menu('frame_wide'), frame_small = menu('frame_small'), pedestal = menu('pedestal');
  static final holo_ring = menu('holo_ring'), glow_orb = menu('glow_orb'), ring = menu('ring'), sparkle = menu('sparkle');
  static final bg_stadium = menu('bg_stadium'), bg_holo = menu('bg_holo');
}
