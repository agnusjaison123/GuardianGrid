import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase/firebase_bootstrap.dart';
import '../core/router/app_router.dart';
import '../core/ui/road_theme.dart';

class GuardianGridApp extends ConsumerWidget {
  const GuardianGridApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseBootstrap = ref.watch(firebaseBootstrapProvider);

    return firebaseBootstrap.when(
      loading: () => MaterialApp(
        title: 'GuardianGrid',
        theme: RoadUi.buildTheme(),
        debugShowCheckedModeBanner: false,
        home: const _StartupPage(
          title: 'Starting GuardianGrid',
          subtitle: 'Connecting to Firebase services...',
          loading: true,
        ),
      ),
      error: (error, stackTrace) => MaterialApp(
        title: 'GuardianGrid',
        theme: RoadUi.buildTheme(),
        debugShowCheckedModeBanner: false,
        home: _StartupPage(
          title: 'Firebase setup required',
          subtitle:
              'Open the app after running FlutterFire configuration.\n$error',
          loading: false,
          onRetry: () => ref.invalidate(firebaseBootstrapProvider),
        ),
      ),
      data: (_) {
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(
          title: 'GuardianGrid',
          theme: RoadUi.buildTheme(),
          debugShowCheckedModeBanner: false,
          routerConfig: router,
        );
      },
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage({
    required this.title,
    required this.subtitle,
    required this.loading,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RoadBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: RoadPanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const CircularProgressIndicator(color: RoadUi.caution)
                    else
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 42,
                        color: RoadUi.caution,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        color: RoadUi.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: RoadUi.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!loading && onRetry != null) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: RoadUi.caution,
                          foregroundColor: const Color(0xFF1D1A0C),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
