import base64,json
from datetime import datetime
from uuid import UUID

def encode(occurred_at, ident):
    raw=json.dumps({'occurred_at':occurred_at.isoformat(),'id':str(ident)},separators=(',',':')).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')
def decode(value):
    try:
        raw=base64.urlsafe_b64decode(value+'='*((4-len(value)%4)%4)); x=json.loads(raw)
        return datetime.fromisoformat(x['occurred_at']), UUID(x['id'])
    except Exception as e: raise ValueError('invalid cursor') from e
