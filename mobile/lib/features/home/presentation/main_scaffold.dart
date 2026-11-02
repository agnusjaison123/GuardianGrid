import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/current_location_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/ui/road_theme.dart';

class MainScaffold extends ConsumerWidget {
  const MainScaffold({
    super.key,
    required this.currentIndex,
    required this.child,
  });

  final int currentIndex;
  final Widget child;

  static const _tabs = <_TabItem>[
    _TabItem(route: '/map', label: 'Map', icon: Icons.map_outlined),
    _TabItem(
      route: '/report',
      label: 'Report',
      icon: Icons.add_a_photo_outlined,
    ),
    _TabItem(
      route: '/safe-route',
      label: 'Safe Route',
      icon: Icons.route_outlined,
    ),
    _TabItem(
      route: '/emergency',
      label: 'Emergency',
      icon: Icons.health_and_safety_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(currentLocationProvider);

    final locationState = locationAsync.when(
      data: (value) => value,
      loading: () => const CurrentLocationState(
        label: 'Locating current GPS...',
        available: false,
      ),
      error: (_, _) =>
          const CurrentLocationState(label: 'GPS unavailable', available: false),
    );

    return Scaffold(
      backgroundColor: RoadUi.asphalt900,
      body: RoadBackground(
        showCenterLane: false,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.shield_outlined,
                      color: RoadUi.caution,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text(
                            'Guardian Grid',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              Icon(
                                locationState.available
                                    ? Icons.my_location_rounded
                                    : Icons.location_off_rounded,
                                color: locationState.available
                                    ? const Color(0xFF7CF2B0)
                                    : const Color(0xFFFFD179),
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  locationState.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: locationState.available
                                        ? const Color(0xFFBFF7D8)
                                        : const Color(0xFFFFE2A8),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .signOut();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5FA),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: RoadUi.asphalt800,
          border: Border(top: BorderSide(color: Color(0x333C434F))),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: RoadUi.asphalt800,
            indicatorColor: RoadUi.caution.withValues(alpha: 0.25),
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: RoadUi.caution);
              }
              return const IconThemeData(color: Color(0xFFB3BECC));
            }),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
              states,
            ) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: RoadUi.caution,
                  fontWeight: FontWeight.w700,
                );
              }
              return const TextStyle(
                color: Color(0xFFB3BECC),
                fontWeight: FontWeight.w600,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            height: 76,
            onDestinationSelected: (index) => context.go(_tabs[index].route),
            destinations: _tabs
                .map(
                  (tab) => NavigationDestination(
                    icon: Icon(tab.icon),
                    label: tab.label,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.route,
    required this.label,
    required this.icon,
  });

  final String route;
  final String label;
  final IconData icon;
}
