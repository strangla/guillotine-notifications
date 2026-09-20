from datetime import datetime
from typing import Any
from uuid import UUID
from pydantic import BaseModel, Field, model_validator

class NotificationCreate(BaseModel):
    source_product: str
    event_type: str
    source_event_id: str | None = None
    entity_type: str | None = None
    entity_key: str | None = None
    severity: str
    title: str | None = None
    message: str
    occurred_at: datetime
    dedupe_key: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_fields(self):
        for value in (self.source_product, self.event_type, self.severity, self.message):
            if not value.strip(): raise ValueError("required text fields must be non-empty")
        if (self.entity_type is None) != (self.entity_key is None):
            raise ValueError("entity_type and entity_key must be provided together")
        return self

class NotificationOut(NotificationCreate):
    id: UUID
    created_at: datetime
    is_read: bool
    read_at: datetime | None

class NotificationList(BaseModel):
    items: list[NotificationOut]
    total: int

class BuildInfo(BaseModel):
    app: str = "notifications"
    source_sha: str

class ImportQuantRow(BaseModel):
    id: UUID
    alert_id: str
    symbol: str
    message: str
    triggered_at: datetime
    read: bool
    priority: str
    source: str
    legacy_id: str | None = None
    legacy_position: int | None = None
