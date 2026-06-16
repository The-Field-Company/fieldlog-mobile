import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import '../services/powersync_service.dart';
import '../services/connectivity_service.dart';

class BrowseSessionsScreen extends StatefulWidget {
  const BrowseSessionsScreen({super.key});

  @override
  State<BrowseSessionsScreen> createState() => _BrowseSessionsScreenState();
}

class _BrowseSessionsScreenState extends State<BrowseSessionsScreen> {
  List<Session> _sessions = [];
  // IDs of sessions the user is currently subscribed to (from local DB).
  Set<int> _subscribedIds = {};
  // IDs of sessions with an in-flight subscribe/unsubscribe request.
  final Set<int> _loadingIds = {};
  bool _loading = true;
  String? _error;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.isOnline;
    _connectivitySubscription = ConnectivityService.stream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadSessions();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await ApiService.getPublicSessions();
      final subscribedIds = await _fetchSubscribedIds();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _subscribedIds = subscribedIds;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load sessions. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<Set<int>> _fetchSubscribedIds() async {
    final db = PowerSyncService.getPowerSync();
    if (db == null) return {};
    final rows = await db.getAll(
      'SELECT session_id FROM fieldlog_sessionsubscription',
    );
    return rows
        .map((row) => int.tryParse(row['session_id']?.toString() ?? '') ?? 0)
        .where((id) => id != 0)
        .toSet();
  }

  Future<void> _subscribe(Session session) async {
    setState(() => _loadingIds.add(session.id));
    try {
      final db = PowerSyncService.getPowerSync();
      if (db == null) throw Exception('Database not ready');

      // Write the subscription locally. PowerSync queues and uploads this to
      // the server. id = session_id.toString() so the server sync returns the
      // same id and PowerSync reconciles without creating a duplicate row.
      await db.execute(
        'INSERT OR IGNORE INTO fieldlog_sessionsubscription (id, session_id)'
        ' VALUES (?, ?)',
        [session.id.toString(), session.id],
      );

      final params = [
        session.id.toString(),
        session.name,
        session.description,
        jsonEncode(session.formConfig),
        session.isActive ? 1 : 0,
        session.isPublic ? 1 : 0,
        session.createdAt,
      ];
      // Cache session data so the entry screen can show the session even if
      // PowerSync clears fieldlog_session before the upload is confirmed.
      await db.execute(
        'INSERT OR REPLACE INTO local_sessions'
        ' (id, name, description, form_config, is_active, is_public, created_at)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?)',
        params,
      );
      // Optimistic upsert for immediate display in the entry screen.
      await db.execute(
        'INSERT OR REPLACE INTO fieldlog_session'
        ' (id, name, description, form_config, is_active, is_public, created_at)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?)',
        params,
      );

      if (!mounted) return;
      setState(() => _subscribedIds.add(session.id));
    } catch (_) {
      if (!mounted) return;
      _showError('Could not subscribe. Try again.');
    } finally {
      if (mounted) setState(() => _loadingIds.remove(session.id));
    }
  }

  Future<void> _unsubscribe(Session session) async {
    setState(() => _loadingIds.add(session.id));
    try {
      final db = PowerSyncService.getPowerSync();
      if (db == null) throw Exception('Database not ready');

      // Delete subscription locally — PowerSync uploads the delete to the server.
      await db.execute(
        'DELETE FROM fieldlog_sessionsubscription WHERE id = ?',
        [session.id.toString()],
      );
      // Remove from both caches for immediate display update.
      await db.execute(
        'DELETE FROM local_sessions WHERE id = ?',
        [session.id.toString()],
      );
      await db.execute(
        'DELETE FROM fieldlog_session WHERE id = ?',
        [session.id.toString()],
      );

      if (!mounted) return;
      setState(() => _subscribedIds.remove(session.id));
    } catch (_) {
      if (!mounted) return;
      _showError('Could not unsubscribe. Try again.');
    } finally {
      if (mounted) setState(() => _loadingIds.remove(session.id));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Browse Sessions',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.primaryBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _isOnline ? _loadSessions : null,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner
          if (!_isOnline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'You\'re offline. Showing cached data.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isOnline ? _loadSessions : null,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No public sessions available.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final isSubscribed = _subscribedIds.contains(session.id);
        final isLoading = _loadingIds.contains(session.id);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    : isSubscribed
                        ? OutlinedButton(
                            onPressed: () => _unsubscribe(session),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(
                                  color: AppColors.borderColor),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              'Joined',
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () => _subscribe(session),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              'Join',
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
