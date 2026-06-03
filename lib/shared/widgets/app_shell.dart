import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/router.dart';

/// Responsive app shell.
///
/// - Desktop (>= 900px wide): NavigationRail on the left (no labels)
/// - Tablet (600–899px): NavigationRail with labels
/// - Mobile (< 600px): BottomNavigationBar
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= AppConfig.desktopBreakpoint) {
      return _DesktopShell(child: child);
    } else if (width >= AppConfig.tabletBreakpoint) {
      return _TabletShell(child: child);
    } else {
      return _MobileShell(child: child);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared navigation destinations
// ---------------------------------------------------------------------------

class _NavDestination {
  const _NavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _NavDestination(
    route: AppRoutes.chat,
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: 'Chat',
  ),
  _NavDestination(
    route: AppRoutes.quiz,
    icon: Icons.quiz_outlined,
    selectedIcon: Icons.quiz,
    label: 'Quiz',
  ),
];

int _selectedIndex(BuildContext context) {
  final location = GoRouterState.of(context).matchedLocation;
  final idx = _destinations.indexWhere((d) => location.startsWith(d.route));
  return idx < 0 ? 0 : idx;
}

// ---------------------------------------------------------------------------
// Desktop shell — NavigationRail + optional split-screen
// ---------------------------------------------------------------------------

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selectedIdx = _selectedIndex(context);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIdx,
            onDestinationSelected: (i) =>
                context.go(_destinations[i].route),
            labelType: NavigationRailLabelType.all,
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet shell — compact NavigationRail
// ---------------------------------------------------------------------------

class _TabletShell extends StatelessWidget {
  const _TabletShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selectedIdx = _selectedIndex(context);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIdx,
            onDestinationSelected: (i) =>
                context.go(_destinations[i].route),
            labelType: NavigationRailLabelType.selected,
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile shell — BottomNavigationBar
// ---------------------------------------------------------------------------

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selectedIdx = _selectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIdx,
        onDestinationSelected: (i) =>
            context.go(_destinations[i].route),
        destinations: _destinations
            .map(
              (d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
