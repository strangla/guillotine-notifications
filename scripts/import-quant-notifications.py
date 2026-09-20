#!/usr/bin/env python3
import argparse, asyncio, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1] / 'src'))
from sqlalchemy import text
from notifications_service.database import session_factory
from notifications_service.schemas import ImportQuantRow
from notifications_service.mapping import quant_to_shared

def load(path):
    raw=json.loads(Path(path).read_text()); rows=[]
    for item in raw: rows.append(quant_to_shared(ImportQuantRow(**item)))
    return rows

def norm(v):
    if hasattr(v, 'isoformat'): return v.isoformat()
    return v

def comparable(row):
    return tuple(norm(row[k]) for k in ('id','source_product','event_type','source_event_id','entity_type','entity_key','severity','title','message','occurred_at','is_read','read_at','dedupe_key')) + (json.dumps(row['metadata'],sort_keys=True,default=str),)

async def run(path,dry=False):
    rows=load(path); inserted=unchanged=conflicts=0
    async with session_factory() as s:
      for row in rows:
        old=(await s.execute(text("SELECT id,source_product,event_type,source_event_id,entity_type,entity_key,severity,title,message,occurred_at,created_at,is_read,read_at,dedupe_key,metadata FROM notifications.notifications WHERE id=:id"),{"id":row['id']})).mappings().first()
        if old:
          old=dict(old); old['metadata']=old['metadata'] or {}
          if comparable(old) != comparable(row): conflicts += 1
          else: unchanged += 1
          continue
        inserted += 1
        if not dry:
          await s.execute(text("""INSERT INTO notifications.notifications (id,source_product,event_type,source_event_id,entity_type,entity_key,severity,title,message,occurred_at,is_read,read_at,dedupe_key,metadata) VALUES (:id,:source_product,:event_type,:source_event_id,:entity_type,:entity_key,:severity,:title,:message,:occurred_at,:is_read,:read_at,:dedupe_key,CAST(:metadata AS jsonb))"""), {**row,'metadata':json.dumps(row['metadata'])})
      if conflicts:
        await s.rollback(); print(f'CONFLICT_ROWS={conflicts} WRITE_PERFORMED=no'); raise SystemExit(1)
      if not dry: await s.commit()
      current=(await s.execute(text('SELECT count(*) FROM notifications.notifications'))).scalar_one()
    projected=(current + inserted) if dry else current
    print(f'SOURCE_ROWS={len(rows)} SOURCE_UNIQUE_IDS={len({r["id"] for r in rows})} SOURCE_INVALID_IDS=0 TARGET_EXISTING_ROWS={unchanged} INSERTED_ROWS={inserted} UNCHANGED_ROWS={unchanged} CONFLICT_ROWS=0 INVALID_ROWS=0 FINAL_TARGET_ROWS={projected} WRITE_PERFORMED={"no" if dry else "yes"}')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('path');p.add_argument('--dry-run',action='store_true');a=p.parse_args();asyncio.run(run(a.path,a.dry_run))
