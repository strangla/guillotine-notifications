import os
os.environ['NOTIFICATION_API_KEY']='test-key'
from fastapi.testclient import TestClient
from notifications_service.main import app

def test_api_limits_and_auth():
 c=TestClient(app); assert c.get('/api/ready').status_code==200
 assert c.get('/api/v1/notifications?limit=501',headers={'X-API-Key':'test-key'}).status_code==422
 assert c.get('/api/v1/notifications',headers={'X-API-Key':'bad'}).status_code==401
