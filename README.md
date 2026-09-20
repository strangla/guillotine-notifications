# Shared Notifications Foundation

Phase 1 provides a small durable notification lifecycle for future Quant, Qual, and Analysis adapters.

Products own facts and events. This service owns user-facing notification identity, history, read state, and idempotent creation. Fact != Event != Notification.

This service intentionally has no generic event bus, metrics warehouse, rule engine, delivery channels, or product adapters. Notification listing uses bounded opaque cursor pagination (never OFFSET); schema changes are migration-owned and runtime startup performs no DDL. Read-state and deletion operations accept an optional `source_product` filter; omitting it explicitly targets the global shared set.

The Quant importer is an operator-owned, one-way disposable/transition tool. It supports dry-run, transactional inserts, fail-loud conflicts, and preserves Quant canonical IDs and provenance.
