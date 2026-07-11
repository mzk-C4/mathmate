import 'package:flutter/material.dart';
import 'package:mathmate/about_mathmate_page.dart';
import 'package:mathmate/account_settings_page.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/grade_selection_page.dart';
import 'package:mathmate/help_support_page.dart';
import 'package:mathmate/history_list_page.dart';
import 'package:mathmate/pages/ability_assessment_page.dart';
import 'package:mathmate/profile_radar_chart.dart';
import 'package:mathmate/responsive/breakpoints.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/services/auth_service.dart';
import 'package:mathmate/services/login_page.dart';
import 'package:mathmate/services/theme_service.dart';
import 'package:mathmate/services/update_service.dart';
import 'package:mathmate/services/user_profile_service.dart';
import 'package:mathmate/tutorial_page.dart';

class ProfilePage extends StatefulWidget {
  /// 雷达图动画触发器——每次递增时重建雷达图并重播中心展开动画。
  final ValueNotifier<int>? radarTrigger;

  const ProfilePage({super.key, this.radarTrigger});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserProfileService _profileService = UserProfileService();
  final AbilityScoreService _abilityService = AbilityScoreService();
  /// 动画触发计数器，每次递增时雷达图重建并重播动画
  int _animTrigger = 0;

  @override
  void initState() {
    super.initState();
    _profileService.addListener(_onProfileChanged);
    _profileService.load();
    _abilityService.addListener(_onDataChanged);
    _abilityService.load();
    widget.radarTrigger?.addListener(_onRadarTrigger);
  }

  @override
  void dispose() {
    _profileService.removeListener(_onProfileChanged);
    _abilityService.removeListener(_onDataChanged);
    widget.radarTrigger?.removeListener(_onRadarTrigger);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  /// 每次点击"我的"Tab 时触发雷达图动画重播
  void _onRadarTrigger() {
    if (mounted) setState(() => _animTrigger++);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: <Widget>[
          Positioned(
            top: -70,
            left: 0,
            right: 0,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.elliptical(320, 120),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                context.isDesktop ? (MediaQuery.sizeOf(context).width - 820) / 2 : 18,
                12,
                context.isDesktop ? (MediaQuery.sizeOf(context).width - 820) / 2 : 18,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '我的',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildHeader(cs),
                  const SizedBox(height: 20),
                  // ---- 六维能力雷达图 ----
                  _buildRadarSection(cs),
                  const SizedBox(height: 26),
                  _MenuCard(
                    icon: Icons.settings_outlined,
                    title: '账户设置',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountSettingsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.school_outlined,
                    title: '更换年级',
                    onTap: () async {
                      final int? result = await Navigator.of(context).push<int>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const GradeSelectionPage(isFromSettings: true),
                        ),
                      );
                      if (result != null && mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.radar,
                    title: '能力自评',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AbilityAssessmentPage(isFromSettings: true),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.menu_book_outlined,
                    title: '新手引导',
                    onTap: () async {
                      await HistoryRepository.instance.resetTutorial();
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TutorialPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.dark_mode_outlined,
                    title: '深色模式',
                    onTap: () => _showThemePicker(context),
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.query_stats_rounded,
                    title: '历史记录',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HistoryListPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.help_outline_rounded,
                    title: '帮助与支持',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HelpSupportPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.system_update_rounded,
                    title: '检查更新 (v${UpdateService.currentVersion})',
                    onTap: () => _checkUpdate(context),
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    icon: Icons.info_outline_rounded,
                    title: '关于 MathMate',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AboutMathMatePage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showLogoutDialog(context),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Center(
                          child: Text(
                            '退出登录',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    final ThemeService ts = ThemeService.instance;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('选择主题'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: AppThemeMode.values.map((AppThemeMode mode) {
                  final String label;
                  final IconData icon;
                  switch (mode) {
                    case AppThemeMode.light:
                      label = '浅色模式';
                      icon = Icons.light_mode;
                    case AppThemeMode.dark:
                      label = '深色模式';
                      icon = Icons.dark_mode;
                    case AppThemeMode.system:
                      label = '跟随系统';
                      icon = Icons.settings_brightness;
                  }
                  return RadioListTile<AppThemeMode>(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(icon, size: 20),
                        const SizedBox(width: 8),
                        Text(label),
                      ],
                    ),
                    value: mode,
                    // ignore: deprecated_member_use
                    groupValue: ts.mode,
                    onChanged: (AppThemeMode? v) {
                      if (v != null) {
                        ts.setMode(v);
                        setDialogState(() {});
                      }
                    },
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final auth = AuthService();
    return Align(
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const ClipOval(
              child: Image(
                image: AssetImage('assets/app_icon_final.png'),
                width: 92,
                height: 92,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (auth.isLoggedIn && auth.user != null) ...[
            Text(auth.user!.username,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(auth.user!.role == 'admin' ? '管理员' : auth.user!.role == 'dev' ? '开发者' : '用户',
              style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5))),
          ] else ...[
            Text('未登录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('登录 / 注册'),
            ),
          ],
        ],
      ),
    );
  }

  /// 六维能力雷达图卡片
  Widget _buildRadarSection(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 8),
              Icon(Icons.radar, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                '能力画像',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AbilityAssessmentPage(isFromSettings: true),
                    ),
                  );
                  if (mounted) setState(() => _animTrigger++);
                },
                icon: Icon(Icons.refresh, size: 16, color: cs.primary),
                label: Text(
                  '重新评估',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 通过 Key 变化触发重建 → initState 动画重播
          ProfileRadarChart(
            key: ValueKey<int>(_animTrigger),
            profile: _abilityService.computedProfile,
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)),
    );
    final update = await UpdateService.checkUpdate();
    if (!mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本'), duration: Duration(seconds: 2)),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text('最新版本: ${update.version}\n\n${update.releaseNotes}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
            FilledButton(onPressed: () { Navigator.pop(ctx); UpdateService.downloadAndInstall(update); }, child: const Text('立即更新')),
          ],
        ),
      );
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final auth = AuthService();
    if (!auth.isLoggedIn) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text('确定以 ${auth.user?.username ?? ""} 的身份退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await auth.logout();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      shadowColor: cs.shadow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
