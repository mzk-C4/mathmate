import 'package:flutter/material.dart';
import 'package:mathmate/about_mathmate_page.dart';
import 'package:mathmate/account_settings_page.dart';
import 'package:mathmate/grade_selection_page.dart';
import 'package:mathmate/help_support_page.dart';
import 'package:mathmate/history_list_page.dart';
import 'package:mathmate/services/theme_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
                      onTap: () {},
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
          Text(
            'MathMate_User',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Level: Math Explorer',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5)),
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
