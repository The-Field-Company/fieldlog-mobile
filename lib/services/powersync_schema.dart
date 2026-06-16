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
]);
