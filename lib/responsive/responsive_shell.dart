import 'package:flutter/material.dart';
import 'package:mathmate/responsive/breakpoints.dart';

/// 单个导航 Tab 的描述（图标 + 文案）。
///
/// 窄屏的 [NavigationBar] 与宽屏的 [NavigationRail] 共用同一份描述，
/// 避免维护两套 item 列表。
class NavTab {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavTab({
    required this.icon,
    required this.label,
    IconData? selectedIcon,
  }) : selectedIcon = selectedIcon ?? icon;
}

/// 响应式导航壳。
///
/// - 窄屏（宽度 < [kDesktopBreakpoint]）：Material 3 [NavigationBar]。
/// - 宽屏：左侧 [NavigationRail]（展开态）+ 右侧内容区，中间一条分隔线。
///
/// 两端共用同一份 [pages]，通过 [IndexedStack] 保留各 Tab 的状态，
/// 切换形态时不会重建子页面。状态（当前选中索引）由调用方持有并透传。
class ResponsiveShell extends StatelessWidget {
  final int currentIndex;

  /// 选中新 Tab 的回调。
  final ValueChanged<int> onTap;

  /// 各 Tab 对应的页面，按顺序与 [tabs] 一一对应。
  final List<Widget> pages;

  /// 各 Tab 的描述（图标 + 文案）。
  final List<NavTab> tabs;

  const ResponsiveShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.pages,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = context.isDesktop;
    // IndexedStack 复用同一实例，切换形态时子页面状态不丢失。
    final Widget content = IndexedStack(index: currentIndex, children: pages);

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            _buildRail(context),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    // 窄屏：Material 3 底部导航，始终显示标签并区分选中图标。
    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: <NavigationDestination>[
          for (final NavTab tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
              tooltip: tab.label,
            ),
        ],
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      extended: true,
      minExtendedWidth: 260,
      backgroundColor: cs.surface,
      destinations: <NavigationRailDestination>[
        for (final NavTab tab in tabs)
          NavigationRailDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: Text(tab.label),
          ),
      ],
    );
  }
}
