import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('exporter',Path(__file__).parents[1]/'scripts/export-quant-compatible-notifications.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def test_export_rejects_non_quant():
    try: m.reconstruct({'source_product':'qual','metadata':{},'entity_key':'AAPL'})
    except ValueError: return
    assert False, 'non-Quant row was accepted'

def test_historical_and_native_rollback_rows():
 base={'source_product':'quant','entity_key':'AAPL','message':'m','occurred_at':__import__('datetime').datetime(2026,1,1,tzinfo=__import__('datetime').timezone.utc),'is_read':False,'severity':'high','metadata':{'quant_alert_id':'a','quant_source':'user_alert','quant_legacy_id':'l','quant_legacy_position':2}}
 out=m.reconstruct({'id':'00000000-0000-0000-0000-000000000001',**base}); assert out['id']== '00000000-0000-0000-0000-000000000001' and out['legacy_id']=='l'
 native={**base,'metadata':{'quant_alert_id':'a','quant_source':'auto_scan'}}; out=m.reconstruct({'id':'00000000-0000-0000-0000-000000000002',**native}); assert out['id']=='00000000-0000-0000-0000-000000000002' and out['legacy_id'] is None
