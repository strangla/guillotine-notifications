import importlib.util
from pathlib import Path
from datetime import datetime, timezone
spec=importlib.util.spec_from_file_location('imp',Path(__file__).parents[1]/'scripts/import-quant-notifications.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def test_quant_mapping_roundtrip_fields():
 r={'id':'00000000-0000-0000-0000-000000000001','alert_id':'a','symbol':'AAPL','message':'m','triggered_at':'2026-01-01T00:00:00+00:00','read':True,'priority':'high','source':'user_alert','legacy_id':'legacy','legacy_position':2}
 from notifications_service.mapping import quant_to_shared
 x=quant_to_shared(m.ImportQuantRow(**r)); assert str(x['id'])==r['id'] and x['entity_key']=='AAPL' and x['is_read'] is True and x['title'] is None
 assert x['metadata']
