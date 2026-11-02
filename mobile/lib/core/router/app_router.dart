import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/emergency/presentation/emergency_page.dart';
import '../../features/hazard/presentation/report_hazard_page.dart';
import '../../features/home/presentation/main_scaffold.dart';
import '../../features/map/presentation/map_page.dart';
import '../../features/navigation/presentation/safe_navigation_page.dart';
import '../ui/road_theme.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final isAuthLoading = authState.isLoading;
  final isLoggedIn = authState.asData?.value != null;

  return GoRouter(
    initialLocation: '/auth-loading',
    redirect: (context, state) {
      final currentPath = state.matchedLocation;
      final isLoadingRoute = currentPath == '/auth-loading';
      final isLoginRoute = state.matchedLocation == '/login';

      if (isAuthLoading) {
        return isLoadingRoute ? null : '/auth-loading';
      }

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      if (!isLoggedIn && isLoadingRoute) {
        return '/login';
      }

      if (isLoggedIn && (isLoginRoute || isLoadingRoute)) {
        return '/map';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth-loading',
        builder: (context, state) => const _AuthLoadingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/map',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 0, child: MapPage()),
      ),
      GoRoute(
        path: '/report',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 1, child: ReportHazardPage()),
      ),
      GoRoute(
        path: '/safe-route',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 2, child: SafeNavigationPage()),
      ),
      GoRoute(
        path: '/emergency',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 3, child: EmergencyPage()),
      ),
    ],
  );
});

class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: RoadBackground(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: RoadPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(color: RoadUi.caution),
                  SizedBox(height: 12),
                  Text(
                    'Checking session...',
                    style: TextStyle(
                      color: RoadUi.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
