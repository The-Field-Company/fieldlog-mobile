import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import '../models/session.dart';
import 'powersync_schema.dart';
import 'powersync_connector.dart';
import 'connectivity_service.dart';

/// PowerSync database service mirroring ui/src/services/powersync/index.js
class PowerSyncService {
  static PowerSyncDatabase? _db;

  static Future<PowerSyncDatabase> initPowerSync() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/fieldlog.db';

    final db = PowerSyncDatabase(
      schema: schema,
      path: dbPath,
    );
    await db.initialize();
    await db.connect(connector: FieldLogConnector());

    _db = db;

    // When the OS reports network restored, immediately trigger a PowerSync
    // reconnect instead of waiting for its own exponential-backoff timer.
    // connect() is a no-op when already connected, so this is always safe.
    ConnectivityService.stream.listen((isOnline) {
      if (isOnline && _db != null) {
        _db!.connect(connector: FieldLogConnector());
      }
    });

    return db;
  }

  static PowerSyncDatabase? getPowerSync() {
    return _db;
  }

  /// Upserts subscribed sessions into local_sessions (a local-only table)
  /// immediately after login, before PowerSync's own sync cycle catches up.
  /// We intentionally do NOT write to fieldlog_session here: that table is
  /// managed by PowerSync and any write to it generates a CRUD queue entry
  /// that must be uploaded before submission entries can be processed.
  /// local_sessions carries zero CRUD overhead and is union-queried by the
  /// entry screen alongside fieldlog_session, so sessions are visible
  /// immediately without polluting the upload queue.
  /// Best-effort — wrap call in try/catch so failures do not block app startup.
  static Future<void> seedSessions(List<Session> sessions) async {
    if (_db == null) return;
    for (final session in sessions) {
      await _db!.execute(
        'INSERT OR REPLACE INTO local_sessions'
        ' (id, name, description, form_config, is_active, is_public, created_at)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          session.id.toString(),
          session.name,
          session.description,
          jsonEncode(session.formConfig),
          session.isActive ? 1 : 0,
          session.isPublic ? 1 : 0,
          session.createdAt,
        ],
      );
    }
  }

  static Future<void> disconnectPowerSync() async {
    if (_db != null) {
      // disconnectAndClear clears all managed tables, local-only tables, and
      // the CRUD upload queue, so no stale data or pending ops carry over to
      // the next user session on the same device.
      await _db!.disconnectAndClear();
      _db = null;
    }
  }
}
