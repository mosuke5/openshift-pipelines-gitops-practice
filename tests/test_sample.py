import pytest
import json
from app import app

def test_healthcheck():
    response = app.test_client().get('/healthcheck')
    res = json.loads(response.data.decode('utf-8'))
    assert response.status_code == 200
    assert res['healthcheck'] == 'ok'
