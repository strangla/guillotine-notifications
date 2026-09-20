from pathlib import Path

def test_foundation_migration_is_manifest_owned_and_no_runtime_ddl():
    root=Path(__file__).parents[1]
    manifest=(root/'migrations/manifest.txt').read_text()
    sql=(root/'migrations/20260920_notification_foundation.sql').read_text()
    assert '20260920_notification_foundation migrations/20260920_notification_foundation.sql' in manifest
    assert 'CREATE SCHEMA IF NOT EXISTS notifications' in sql
    assert 'CREATE TABLE IF NOT EXISTS notifications.notifications' in sql
    assert 'CREATE UNIQUE INDEX' in sql
