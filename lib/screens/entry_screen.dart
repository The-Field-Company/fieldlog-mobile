import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../theme/app_colors.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/preferences_service.dart';
import '../services/powersync_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/sync_status_widget.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  String? _username;
  Session? _cachedSession;
  List<Session> _subscriptions = [];
  bool _isOnline = true;

  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadCachedSession();
    _isOnline = ConnectivityService.isOnline;
    _connectivitySubscription = ConnectivityService.stream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _listenToSessions();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsernameAsync();
    if (mounted) setState(() => _username = username);
  }

  Future<void> _loadCachedSession() async {
    final session = await PreferencesService.getCachedSession();
    if (mounted) setState(() => _cachedSession = session);
  }

  void _listenToSessions() {
    final db = PowerSyncService.getPowerSync();
    if (db == null) return;
    _sessionSubscription = db
        .watch(
          'SELECT * FROM fieldlog_session'
          ' UNION'
          ' SELECT * FROM local_sessions'
          '   WHERE id NOT IN (SELECT id FROM fieldlog_session)'
          ' ORDER BY name ASC',
        )
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _subscriptions = rows.map((row) => Session.fromRow(row)).toList();
      });
    });
  }

  Future<void> _logout() async {
    // disconnectAndClear() wipes all managed tables, local-only tables, and the
    // CRUD upload queue — no manual DELETE needed and no stale data or pending
    // ops carry over to the next user on this device.
    try {
      await PowerSyncService.disconnectPowerSync();
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
    }
    await AuthService.logout();
    await PreferencesService.clearCachedSession();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (_username != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _username!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  const SyncStatusWidget(),
                  if (_isOnline)
                    IconButton(
                      icon: const Icon(Icons.explore_outlined,
                          color: AppColors.accent),
                      onPressed: () => Navigator.pushNamed(context, '/browse'),
                      tooltip: 'Browse sessions',
                    ),
                  IconButton(
                    icon: const Icon(Icons.logout_outlined,
                        color: AppColors.textTertiary),
                    onPressed: _logout,
                    tooltip: 'Sign out',
                  ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                children: [
                  const SizedBox(height: 24),

                  // Logo
                  Center(
                    child: Image.asset('assets/logo.png', height: 100),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Scientific Field Data Collection',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Continue previous session shortcut
                  if (_cachedSession != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/form',
                            arguments: _cachedSession,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow_rounded, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Continue: ${_cachedSession!.name}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Section header
                  Text(
                    'Sessions',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sessions list or empty state
                  if (_subscriptions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 40,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No sessions yet.',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isOnline
                                ? 'Tap Browse to find and join a session.'
                                : 'Go online to browse and join sessions.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._subscriptions.map((session) => _SessionCard(
                          session: session,
                          onTap: () async {
                            final nav = Navigator.of(context);
                            await PreferencesService.cacheSession(session);
                            if (!mounted) return;
                            nav.pushNamed('/form', arguments: session);
                          },
                        )),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (session.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        session.description,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
