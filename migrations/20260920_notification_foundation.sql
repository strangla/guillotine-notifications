CREATE SCHEMA IF NOT EXISTS notifications;

CREATE TABLE IF NOT EXISTS notifications.notifications (
    id UUID PRIMARY KEY,
    source_product TEXT NOT NULL CHECK (source_product <> ''),
    event_type TEXT NOT NULL CHECK (event_type <> ''),
    source_event_id TEXT,
    entity_type TEXT,
    entity_key TEXT,
    severity TEXT NOT NULL CHECK (severity <> ''),
    title TEXT,
    message TEXT NOT NULL CHECK (message <> ''),
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    dedupe_key TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT notification_entity_pair CHECK ((entity_type IS NULL) = (entity_key IS NULL)),
    CONSTRAINT notification_read_timestamp CHECK (read_at IS NULL OR is_read = TRUE)
);

CREATE UNIQUE INDEX IF NOT EXISTS notifications_source_dedupe_uq
    ON notifications.notifications (source_product, dedupe_key)
    WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS notifications_order_idx
    ON notifications.notifications (occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS notifications_unread_idx
    ON notifications.notifications (is_read, occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS notifications_entity_idx
    ON notifications.notifications (entity_type, entity_key, occurred_at DESC);
