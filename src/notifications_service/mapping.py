from datetime import datetime
from typing import Any
from uuid import UUID
from .schemas import ImportQuantRow

ALLOWED_SOURCES = {"user_alert": "quant.user_alert", "auto_scan": "quant.auto_scan"}

def quant_to_shared(row: ImportQuantRow) -> dict[str, Any]:
    if row.source not in ALLOWED_SOURCES:
        raise ValueError(f"unknown Quant source: {row.source}")
    return {"id": row.id, "source_product":"quant", "event_type":ALLOWED_SOURCES[row.source], "source_event_id":None, "entity_type":"security", "entity_key":row.symbol, "severity":row.priority, "title":None, "message":row.message, "occurred_at":row.triggered_at, "is_read":row.read, "read_at":None, "dedupe_key":None, "metadata":{"quant_alert_id":row.alert_id,"quant_source":row.source,"quant_legacy_id":row.legacy_id,"quant_legacy_position":row.legacy_position}}

def shared_to_quant(row: dict[str, Any]) -> dict[str, Any]:
    source = row["metadata"].get("quant_source")
    if source not in ALLOWED_SOURCES: raise ValueError("shared row lacks supported Quant provenance")
    return {"id":str(row["id"]), "alert_id":row["metadata"].get("quant_alert_id"), "symbol":row["entity_key"], "message":row["message"], "triggered_at":row["occurred_at"], "read":row["is_read"], "priority":row["severity"], "source":source, "legacy_id":row["metadata"].get("quant_legacy_id"), "legacy_position":row["metadata"].get("quant_legacy_position")}
