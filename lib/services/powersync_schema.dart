import 'package:powersync/powersync.dart';

/// PowerSync schema mirroring ui/src/services/powersync/schema.js
/// The `id` column is auto-created by PowerSync (UUID primary key).
const schema = Schema([
  Table('fieldlog_submission', [
    Column.integer('session_id'),
    Column.text('submitted_by'),
    Column.text('data'),
    Column.text('submitted_at'),
  ]),
  Table('fieldlog_session', [
    Column.text('name'),
    Column.text('description'),
    Column.text('form_config'),   // JSON string — parse with jsonDecode when reading
    Column.integer('is_active'),
    Column.integer('is_public'),
    Column.text('created_at'),
  ]),
  // Bidirectional sync: writes are uploaded via uploadData(); rows sync down
  // from the server using session_id::text as the row id so client and server
  // always agree on the key (no duplicate-row reconciliation needed).
  Table('fieldlog_sessionsubscription', [
    Column.integer('session_id'),
  ]),
  // Local-only session data cache. Never synced. Keeps session details visible
  // during the window between subscription upload and PowerSync confirming the
  // row in fieldlog_session. Cleared on logout via disconnectAndClear().
  Table.localOnly('local_sessions', [
    Column.text('name'),
    Column.text('description'),
    Column.text('form_config'),
    Column.integer('is_active'),
    Column.integer('is_public'),
    Column.text('created_at'),
  ]),
]);
