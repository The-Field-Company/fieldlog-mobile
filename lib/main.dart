import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/entry_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/form_screen.dart';
import 'screens/success_screen.dart';
import 'screens/browse_sessions_screen.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/powersync_service.dart';
import 'services/connectivity_service.dart';

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('GLITCHTIP_DSN');
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.01;
      options.environment = kDebugMode ? 'debug' : 'production';
      options.sendDefaultPii = false;
      options.enableAutoSessionTracking = false;
    },
    appRunner: () async {
      // Initialise OS-level connectivity before anything else so the signal is
      // ready before the first widget mounts.
      await ConnectivityService.init();

      // Restore session: check if user is still authenticated
      String initialRoute = '/login';
      final sessionValid = await AuthService.initSession();
      if (sessionValid) {
        initialRoute = '/';
        try {
          await PowerSyncService.initPowerSync();
          // Seed subscribed sessions immediately so the entry screen has data
          // before PowerSync's own sync cycle delivers rows. Best-effort.
          try {
            final subscriptions = await ApiService.getSubscriptions();
            await PowerSyncService.seedSessions(subscriptions);
          } catch (e, stackTrace) {
            await Sentry.captureException(e, stackTrace: stackTrace);
            if (kDebugMode) debugPrint('[Seed] subscription seed failed: $e');
          }
        } catch (e, stackTrace) {
          await Sentry.captureException(e, stackTrace: stackTrace);
          if (kDebugMode) debugPrint('[PowerSync] init failed on startup: $e');
        }
      }

      runApp(FieldLogApp(initialRoute: initialRoute));
    },
  );
}

class FieldLogApp extends StatelessWidget {
  final String initialRoute;

  const FieldLogApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldLog',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      navigatorObservers: [SentryNavigatorObserver()],
      routes: {
        '/login': (context) => const LoginScreen(),
        '/': (context) => const EntryScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/form': (context) => const FormScreen(),
        '/success': (context) => const SuccessScreen(),
        '/browse': (context) => const BrowseSessionsScreen(),
      },
    );
  }
}
