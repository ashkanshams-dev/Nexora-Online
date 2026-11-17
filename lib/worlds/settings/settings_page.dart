import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../core/online/online_service.dart';
import '../oracle_core/persona/oracle_tour.dart';
import '../../features/admin/admin_access.dart';
import 'account_page.dart';

/// Settings (STEP_12, P13, P16, P27, P28).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    String qLabel(GraphicsQuality q) => switch (q) {
          GraphicsQuality.low => context.tx('کم', 'Low'),
          GraphicsQuality.medium => context.tx('متوسط', 'Medium'),
          GraphicsQuality.high => context.tx('بالا', 'High'),
          GraphicsQuality.ultra => context.tx('فوق‌العاده', 'Ultra'),
        };
    return NxWorldScaffold(
      title: context.tx('تنظیمات', 'SETTINGS'),
      palette: WorldPalette.hub,
      showWallet: false,
      body: ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: [
          _section(context, context.tx('صدا و موسیقی', 'Sound & music')),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.music,
                onChanged: (v) => s.music = v,
                secondary: const Icon(Icons.music_note_rounded),
                title: Text(context.tx('موسیقی منو', 'Menu music')),
                subtitle: Text(context.tx(
                    'در منوها پخش می‌شود و داخل بازی آرام قطع می‌شود',
                    'Plays on menus, fades out inside games')),
              ),
              Row(children: [
                const Icon(Icons.volume_down_rounded, color: NxColors.textDim),
                Expanded(
                  child: Slider(
                    value: s.musicVolume,
                    onChanged: s.music ? (v) => s.musicVolume = v : null,
                    label: '${(s.musicVolume * 100).round()}%',
                    divisions: 20,
                  ),
                ),
                const Icon(Icons.volume_up_rounded, color: NxColors.textDim),
              ]),
            ]),
          ),
          _section(context, context.tx('گرافیک و حرکت', 'Graphics & motion')),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tx('کیفیت گرافیک', 'Graphics quality'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SegmentedButton<GraphicsQuality>(
                segments: [
                  for (final q in GraphicsQuality.values)
                    ButtonSegment(value: q, label: Text(qLabel(q))),
                ],
                selected: {s.quality},
                onSelectionChanged: (v) => s.quality = v.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(
                context.tx(
                    'کیفیت کمتر = ستاره، ذره و جلوه‌ی کمتر و باتری بیشتر.',
                    'Lower quality = fewer stars, particles and effects, better battery.'),
                style: const TextStyle(color: NxColors.textDim, fontSize: 12),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.reducedMotion,
                onChanged: (v) => s.reducedMotion = v,
                title: Text(context.tx('کاهش حرکت', 'Reduced motion')),
                subtitle: Text(context.tx(
                    'انیمیشن‌های بلند و حرکت دوربین خاموش',
                    'Disable long animations and camera moves')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.haptics,
                onChanged: (v) => s.haptics = v,
                title: Text(context.tx('لرزش لمسی', 'Haptics')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.sound,
                onChanged: (v) => s.sound = v,
                title: Text(context.tx('بازخورد بازی‌ها', 'Game feedback')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.oracleBuddy,
                onChanged: (v) => s.oracleBuddy = v,
                title: Text(context.tx('اوراکل شیطون گوشه‌ی صفحه', 'Corner ORACLE buddy')),
                subtitle: Text(context.tx('بکش تا جابه‌جا شود؛ دو بار بزن تا کوچک شود؛ نگه دار تا گفتگو باز شود',
                    'Drag to move; double-tap to minimise; long-press to chat')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.oracleTalk,
                onChanged: s.oracleBuddy ? (v) => s.oracleTalk = v : null,
                title: Text(context.tx('حرف زدن اوراکل', 'ORACLE speech bubbles')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tour_rounded, color: Color(0xFF8FF3FF)),
                title: Text(context.tx('دیدن دوباره‌ی تور اوراکل', 'Replay ORACLE tour')),
                subtitle: Text(context.tx('راهنمای قدم‌به‌قدم هر بخش دوباره نشان داده می‌شود',
                    'Every section shows its step-by-step guide again')),
                onTap: () async {
                  final client = ref.read(onlineProvider).client;
                  await OracleTourStore.reset(client?.auth.currentUser?.id, client: client);
                  OracleTourStore.replayTick.value++;
                },
              ),
              const _AdminInviteTile(),
              const _OracleAdminTile(),
            ]),
          ),
          _section(context, context.tx('زبان', 'Language')),
          GlassPanel(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fa', label: Text('فارسی')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.languageCode},
              onSelectionChanged: (v) => s.languageCode = v.first,
              showSelectedIcon: false,
            ),
          ),
          _section(context, context.tx('حساب و داده', 'Account & data')),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Explorer ID: ${p.explorerId}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: visual.text)),
              const SizedBox(height: 4),
              Text(
                context.tx(
                    'یک نسخه از داده‌ها همیشه روی همین گوشی می‌ماند (کار آفلاین).',
                    'A copy of your data always stays on this phone (works offline).'),
                style: const TextStyle(color: NxColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const AccountStatusCard(),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: NxColors.danger),
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(context.tx('حذف هویت و همه‌ی داده‌ها',
                    'Delete identity and all data')),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.tx('مطمئنی؟', 'Are you sure?')),
                      content: Text(ctx.tx(
                          'همه‌ی پیشرفت، آیتم‌ها و پست‌ها پاک می‌شوند. قابل بازگشت نیست.',
                          'All progress, items and posts will be erased. This cannot be undone.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(ctx.tx('انصراف', 'Cancel'))),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: NxColors.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(ctx.tx('حذف', 'Delete')),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final store = LocalStore.instance;
                    for (final k in store.prefs.getKeys().toList()) {
                      if (!k.startsWith('settings.')) await store.remove(k);
                    }
                    await p.resetAll();
                    if (context.mounted) context.go('/onboarding');
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: NxSpace.xl),
          Center(
            child: Text(
                'NEXORA · YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: NxColors.textDim.withValues(alpha: 0.6),
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, NxSpace.lg, 4, NxSpace.sm),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: NxThemeColors.of(context).accent,
                letterSpacing: 0.5)),
      );

}


/// Any signed-in user can redeem the one-time code issued by the main admin.
/// The server, not this widget, decides whether the code and account are valid.
class _AdminInviteTile extends ConsumerWidget {
  const _AdminInviteTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.vpn_key_rounded, color: Color(0xFF8FF3FF)),
        title: Text(context.tx('ورود کد دعوت ادمین', 'Redeem admin invitation code')),
        subtitle: Text(context.tx('کد را از مدیر اصلی بگیر', 'Use a code issued by the main admin')),
        onTap: () async {
          final TextEditingController code = TextEditingController();
          final String? value = await showDialog<String>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: Text(ctx.tx('کد دعوت ادمین', 'Admin invitation code')),
              content: TextField(
                controller: code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'NX-XXXXXXXX'),
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tx('انصراف', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, code.text), child: Text(ctx.tx('ثبت', 'Redeem'))),
              ],
            ),
          );
          code.dispose();
          if (value == null || value.trim().isEmpty || !context.mounted) return;
          final Map<String, dynamic> result = await AdminApi(ref.read(onlineProvider)).redeemAdminCode(value);
          if (!context.mounted) return;
          final bool fa = context.isFa;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['ok'] == true
                ? (fa ? 'دسترسی ساخت تورنمنت فعال شد ✓' : 'Tournament-admin access enabled ✓')
                : adminErrorText(result['error'] as String?, fa)),
          ));
          if (result['ok'] == true) await ref.read(adminAccessProvider).refresh();
        },
      );
}

/// Admin entries: the admin panel for any admin, the ORACLE form for the 'oracle' permission (server re-checks).
class _OracleAdminTile extends ConsumerWidget {
  const _OracleAdminTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    if (!a.isAdmin) return const SizedBox.shrink();
    return Column(children: <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFFC857)),
        title: Text(a.owner ? context.tx('پنل مدیر اصلی', 'Main admin panel') : context.tx('پنل مدیریت', 'Admin panel')),
        onTap: () => context.push('/admin'),
      ),
      if (a.can(AdminPerm.oracle))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_alt_rounded, color: Color(0xFFFFC857)),
          title: Text(context.tx('تنظیمات شخصیت اوراکل (مدیر)', 'ORACLE personality config (admin)')),
          onTap: () => context.push('/admin/oracle'),
        ),
    ]);
  }
}
