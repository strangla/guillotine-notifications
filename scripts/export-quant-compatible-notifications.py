#!/usr/bin/env python3
import argparse,asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'src'))
from sqlalchemy import text
from notifications_service.database import session_factory

def reconstruct(row):
 if row['source_product']!='quant': raise ValueError('non-Quant row selected')
 m=row['metadata'] or {}; source=m.get('quant_source'); alert=m.get('quant_alert_id')
 if source not in {'user_alert','auto_scan'} or not alert or not row['entity_key']: raise ValueError('invalid Quant provenance')
 return {'id':str(row['id']),'alert_id':alert,'symbol':row['entity_key'],'message':row['message'],'triggered_at':row['occurred_at'].isoformat(),'read':row['is_read'],'priority':row['severity'],'source':source,'legacy_id':m.get('quant_legacy_id'),'legacy_position':m.get('quant_legacy_position')}
async def run(path):
 async with session_factory() as s:
  rows=(await s.execute(text("SELECT id,source_product,entity_key,message,occurred_at,is_read,severity,metadata FROM notifications.notifications WHERE source_product='quant' ORDER BY occurred_at DESC,id DESC"))).mappings().all()
 payload=[reconstruct(dict(r)) for r in rows]; Path(path).write_text(json.dumps(payload,indent=2)+'\n'); print(f'EXPORTED_ROWS={len(payload)} OUTPUT={path}')
if __name__=='__main__': p=argparse.ArgumentParser();p.add_argument('path');asyncio.run(run(p.parse_args().path))
