# Shared Notifications Foundation

Phase 1 provides a small durable notification lifecycle for future Quant, Qual, and Analysis adapters.

Products own facts and events. This service owns user-facing notification identity, history, read state, and idempotent creation. Fact != Event != Notification.

This foundation intentionally has no generic event bus, metrics warehouse, rule engine, delivery channels, pagination cursor, or product adapters. Schema changes are migration-owned; runtime startup performs no DDL.

The Quant importer is an operator-owned, one-way disposable/transition tool. It supports dry-run, transactional inserts, fail-loud conflicts, and preserves Quant canonical IDs and provenance.
