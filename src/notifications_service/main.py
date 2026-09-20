from fastapi import FastAPI, Header, HTTPException, Query
from .config import settings
from .schemas import NotificationCreate, BuildInfo
from . import service

app=FastAPI(title='Shared Notifications')

def auth(key: str|None):
    if not settings.notification_api_key:
        raise HTTPException(503, 'notification API key is not configured')
    if key != settings.notification_api_key:
        raise HTTPException(401, 'invalid notification API key')

@app.get('/api/ready')
async def ready(): return {'ready':True}
@app.get('/api/build-info', response_model=BuildInfo)
async def build_info(): return BuildInfo(source_sha=settings.source_sha)
@app.post('/api/v1/notifications')
async def create(payload: NotificationCreate, x_api_key: str|None=Header(default=None)):
    auth(x_api_key)
    try: row,created=await service.create(payload)
    except ValueError as e: raise HTTPException(409,str(e))
    return {'notification':row,'created':created}
@app.get('/api/v1/notifications')
async def listing(limit:int=Query(100,ge=1,le=500),source_product:str|None=None,entity_type:str|None=None,entity_key:str|None=None,unread_only:bool=False,x_api_key:str|None=Header(default=None)):
    auth(x_api_key); return {'items':await service.list_notifications(limit,source_product,entity_type,entity_key,unread_only)}
@app.get('/api/v1/notifications/unread-count')
async def unread(x_api_key: str|None=Header(default=None)):
    auth(x_api_key); return {'count':await service.unread_count()}
@app.patch('/api/v1/notifications/{ident}/read')
async def read(ident:str,x_api_key:str|None=Header(default=None)):
    from uuid import UUID
    auth(x_api_key)
    try: ok=await service.mark_read(UUID(ident))
    except ValueError: raise HTTPException(400,'invalid id')
    if not ok: raise HTTPException(404,'not found')
    return {'ok':True}
@app.post('/api/v1/notifications/mark-all-read')
async def all_read(x_api_key:str|None=Header(default=None)):
    auth(x_api_key); return {'marked':await service.mark_all_read()}
