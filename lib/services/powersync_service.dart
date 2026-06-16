import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import '../models/session.dart';
import 'powersync_schema.dart';
import 'powersync_connector.dart';

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
    return db;
  }

  static PowerSyncDatabase? getPowerSync() {
    return _db;
  }

  /// Upserts subscribed sessions into the local DB immediately after login,
  /// before PowerSync's own sync cycle catches up. Best-effort — wrap call in
  /// try/catch so failures do not block app startup.
  static Future<void> seedSessions(List<Session> sessions) async {
    if (_db == null) return;
    for (final session in sessions) {
      await _db!.execute(
        'INSERT OR REPLACE INTO fieldlog_session'
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
      await _db!.disconnect();
      _db = null;
    }
  }
}
