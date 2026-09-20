from datetime import datetime, timezone
from uuid import UUID, uuid4
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from .database import session_factory
from .schemas import NotificationCreate, NotificationOut
from .pagination import encode, decode

COLS = "id, source_product, event_type, source_event_id, entity_type, entity_key, severity, title, message, occurred_at, created_at, is_read, read_at, dedupe_key, metadata"

def _out(row): return NotificationOut(**dict(row._mapping))

async def create(payload: NotificationCreate) -> tuple[NotificationOut, bool]:
    now = datetime.now(timezone.utc)
    async with session_factory() as s:
        if payload.dedupe_key:
            existing = (await s.execute(text(f"SELECT {COLS} FROM notifications.notifications WHERE source_product=:p AND dedupe_key=:d"), {"p":payload.source_product,"d":payload.dedupe_key})).first()
            if existing:
                old = _out(existing)
                immutable = (old.event_type, old.source_event_id, old.entity_type, old.entity_key, old.severity, old.title, old.message, old.occurred_at, old.metadata)
                incoming = (payload.event_type, payload.source_event_id, payload.entity_type, payload.entity_key, payload.severity, payload.title, payload.message, payload.occurred_at, payload.metadata)
                if immutable != incoming: raise ValueError("dedupe key conflicts with existing immutable payload")
                return old, False
        ident = uuid4()
        try:
            await s.execute(text(f"""INSERT INTO notifications.notifications ({COLS}) VALUES (:id,:source_product,:event_type,:source_event_id,:entity_type,:entity_key,:severity,:title,:message,:occurred_at,:created_at,false,NULL,:dedupe_key,CAST(:metadata AS jsonb))"""), {"id":ident, **payload.model_dump(), "created_at":now, "metadata":__import__('json').dumps(payload.metadata)})
            await s.commit()
        except IntegrityError:
            await s.rollback()
            if payload.dedupe_key:
                existing = (await s.execute(text(f"SELECT {COLS} FROM notifications.notifications WHERE source_product=:p AND dedupe_key=:d"), {"p":payload.source_product,"d":payload.dedupe_key})).first()
                if existing:
                    old = _out(existing)
                    incoming=(payload.event_type,payload.source_event_id,payload.entity_type,payload.entity_key,payload.severity,payload.title,payload.message,payload.occurred_at,payload.metadata)
                    current=(old.event_type,old.source_event_id,old.entity_type,old.entity_key,old.severity,old.title,old.message,old.occurred_at,old.metadata)
                    if current == incoming: return old, False
                    raise ValueError("dedupe key conflicts with existing immutable payload")
            raise
        row=(await s.execute(text(f"SELECT {COLS} FROM notifications.notifications WHERE id=:id"),{"id":ident})).first()
        return _out(row), True

async def list_notifications(limit=100, source_product=None, entity_type=None, entity_key=None, unread_only=False, cursor=None):
    clauses=[]; params={}
    if source_product: clauses.append("source_product=:source_product"); params['source_product']=source_product
    if entity_type: clauses.append("entity_type=:entity_type"); params['entity_type']=entity_type
    if entity_key: clauses.append("entity_key=:entity_key"); params['entity_key']=entity_key
    if unread_only: clauses.append("is_read=FALSE")
    if cursor:
        occurred, ident = decode(cursor); clauses.append("(occurred_at < :cursor_time OR (occurred_at = :cursor_time AND id < :cursor_id))"); params.update(cursor_time=occurred,cursor_id=ident)
    where = (' WHERE ' + ' AND '.join(clauses)) if clauses else ''
    async with session_factory() as s:
        rows=(await s.execute(text(f"SELECT {COLS} FROM notifications.notifications{where} ORDER BY occurred_at DESC,id DESC LIMIT :limit"), {**params,'limit':limit+1})).all()
        has_more=len(rows)>limit; rows=rows[:limit]
        return {'items':[_out(r) for r in rows], 'next_cursor': encode(rows[-1].occurred_at,rows[-1].id) if has_more and rows else None}

async def clear_notifications(source_product=None):
    async with session_factory() as s:
        if source_product:
            r=await s.execute(text("DELETE FROM notifications.notifications WHERE source_product=:source"),{'source':source_product})
        else: r=await s.execute(text("DELETE FROM notifications.notifications"))
        await s.commit(); return r.rowcount or 0

async def unread_count(source_product=None):
    async with session_factory() as s:
        if source_product:
            return (await s.execute(text("SELECT count(*) FROM notifications.notifications WHERE is_read=FALSE AND source_product=:source"), {'source':source_product})).scalar_one()
        return (await s.execute(text("SELECT count(*) FROM notifications.notifications WHERE is_read=FALSE"))).scalar_one()

async def mark_read(ident: UUID):
    async with session_factory() as s:
        r=await s.execute(text("UPDATE notifications.notifications SET is_read=TRUE, read_at=COALESCE(read_at, now()) WHERE id=:id RETURNING id"),{"id":ident}); await s.commit(); return r.first() is not None

async def mark_all_read(source_product=None):
    async with session_factory() as s:
        if source_product:
            r=await s.execute(text("UPDATE notifications.notifications SET is_read=TRUE, read_at=COALESCE(read_at, now()) WHERE is_read=FALSE AND source_product=:source"), {'source':source_product})
        else:
            r=await s.execute(text("UPDATE notifications.notifications SET is_read=TRUE, read_at=COALESCE(read_at, now()) WHERE is_read=FALSE"))
        await s.commit(); return r.rowcount
