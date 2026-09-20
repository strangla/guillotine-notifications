import pytest
from notifications_service.mapping import quant_to_shared, shared_to_quant
from notifications_service.schemas import ImportQuantRow

@pytest.mark.parametrize("source,read,legacy_id,legacy_position", [("user_alert",False,None,None),("auto_scan",True,None,None),("user_alert",True,"legacy",1),("auto_scan",False,"legacy",7)])
def test_quant_mapping_roundtrip_all_fields(source,read,legacy_id,legacy_position):
    raw={'id':'00000000-0000-0000-0000-000000000001','alert_id':'a','symbol':'AAPL','message':'m','triggered_at':'2026-01-01T00:00:00+00:00','read':read,'priority':'high','source':source,'legacy_id':legacy_id,'legacy_position':legacy_position}
    restored=shared_to_quant(quant_to_shared(ImportQuantRow(**raw)))
    assert str(restored['id'])==raw['id']; assert restored['alert_id']==raw['alert_id']; assert restored['symbol']==raw['symbol']; assert restored['message']==raw['message']; assert restored['read']==raw['read']; assert restored['priority']==raw['priority']; assert restored['source']==raw['source']; assert restored['legacy_id']==legacy_id; assert restored['legacy_position']==legacy_position

def test_unknown_quant_source_fails_closed():
    raw={'id':'00000000-0000-0000-0000-000000000001','alert_id':'a','symbol':'AAPL','message':'m','triggered_at':'2026-01-01T00:00:00+00:00','read':False,'priority':'high','source':'future_unknown'}
    with pytest.raises(ValueError): quant_to_shared(ImportQuantRow(**raw))
