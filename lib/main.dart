import 'dart:async';
import 'package:app_links/app_links.dart';
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
import 'screens/invite_screen.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/powersync_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_error_service.dart';

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
      await ConnectivityService.init();

      String initialRoute = '/login';
      final sessionValid = await AuthService.initSession();
      if (sessionValid) {
        initialRoute = '/';
        try {
          await PowerSyncService.initPowerSync();
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

      final appLinks = AppLinks();
      Uri? initialLink;
      try {
        initialLink = await appLinks.getInitialLink();
      } catch (_) {}

      runApp(FieldLogApp(
        initialRoute: initialRoute,
        initialLink: initialLink,
        appLinks: appLinks,
      ));
    },
  );
}

class FieldLogApp extends StatefulWidget {
  final String initialRoute;
  final Uri? initialLink;
  final AppLinks appLinks;

  const FieldLogApp({
    super.key,
    required this.initialRoute,
    required this.appLinks,
    this.initialLink,
  });

  @override
  State<FieldLogApp> createState() => _FieldLogAppState();
}

class _FieldLogAppState extends State<FieldLogApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleLink(widget.initialLink!);
      });
    }
    _linkSubscription = widget.appLinks.uriLinkStream.listen(_handleLink);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _handleLink(Uri uri) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    if (segments[0] == 'sessions' && segments.length >= 2) {
      final id = int.tryParse(segments[1]);
      if (id != null) nav.pushNamed('/browse', arguments: id);
    } else if (segments[0] == 'invite' && segments.length >= 2) {
      nav.pushNamed('/invite', arguments: segments[1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldLog',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: SyncErrorService.messengerKey,
      navigatorKey: _navigatorKey,
      initialRoute: widget.initialRoute,
      navigatorObservers: [SentryNavigatorObserver()],
      routes: {
        '/login': (context) => const LoginScreen(),
        '/': (context) => const EntryScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/form': (context) => const FormScreen(),
        '/success': (context) => const SuccessScreen(),
        '/browse': (context) => const BrowseSessionsScreen(),
        '/invite': (context) => const InviteScreen(),
      },
    );
  }
}
