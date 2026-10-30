import asyncio
import time
from dataclasses import replace

import httpx
import pytest

from capa_bridge.delivery import Delivery
from test_bridge import setup, submit


def make_delivery(app, store, handler):
    settings = replace(app.state.service.delivery.settings, apns_bundle_id='com.example.capa',
                       apns_team_id='TEAM', apns_key_id='KEY', apns_key_path='/not-used')
    delivery = Delivery(settings, store, httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    # Signing is independently tested with a real EC key below; do not contact Apple.
    delivery.jwt_token = 'test-jwt'
    delivery.jwt_issued_at = time.time()
    return delivery


def event_for(setup):
    http, app, server, store, headers, paired = setup
    task = submit(http, headers).json()
    server.runs['run-1'] = {'status': 'completed', 'output': 'Research complete.'}
    asyncio.run(app.state.service.reconcile())
    return store.events(paired['device_id'])[0]


def test_disabled_voice_sends_alert_without_task_content(setup):
    http, app, _, store, headers, _ = setup
    event = event_for(setup)
    http.put('/v1/device', headers=headers, json={'available': False, 'notification_token': 'aabb'})
    sent = []
    def handle(request):
        sent.append(request)
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    asyncio.run(delivery.flush())
    assert sent[0].headers['apns-push-type'] == 'alert'
    assert sent[0].headers['apns-topic'] == 'com.example.capa'
    assert b'Research complete' not in sent[0].content
    assert store.events()[0]['notified']
    assert not store.events()[0]['acknowledged']


def test_ptt_success_requires_playback_ack_or_falls_back_to_alert(setup):
    http, app, _, store, headers, _ = setup
    event = event_for(setup)
    http.put('/v1/workspace', headers=headers, json={'reply_mode': 'spoken'})
    http.put('/v1/device', headers=headers, json={'available': True, 'ptt_token': 'aabb',
                                                'notification_token': 'ccdd', 'channel_id': 'channel'})
    sent = []
    def handle(request):
        sent.append(request)
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    asyncio.run(delivery.flush())
    asyncio.run(delivery.flush())
    assert len(sent) == 1
    assert sent[0].headers['apns-push-type'] == 'pushtotalk'
    assert sent[0].headers['apns-topic'] == 'com.example.capa.voip-ptt'
    assert sent[0].headers['apns-expiration'] == '0'
    store.update_event(event['id'], ptt_sent_at=time.time() - 46)
    asyncio.run(delivery.flush())
    assert len(sent) == 2
    assert sent[1].headers['apns-push-type'] == 'alert'


def test_acknowledged_and_revoked_devices_are_not_delivered(setup):
    http, app, _, store, headers, paired = setup
    event = event_for(setup)
    http.put('/v1/device', headers=headers, json={'notification_token': 'aabb'})
    called = []
    def handle(request):
        called.append(request)
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    store.revoke_device(paired['device_id'])
    asyncio.run(delivery.flush())
    assert called == []


def test_push_failure_is_retryable_and_result_stays_pending(setup):
    http, app, _, store, headers, _ = setup
    event_for(setup)
    http.put('/v1/device', headers=headers, json={'notification_token': 'aabb'})
    delivery = make_delivery(app, store, lambda request: httpx.Response(503))
    asyncio.run(delivery.flush())
    event = store.events()[0]
    assert not event['notified']
    assert event['attempts'] == 1
    assert event['next_attempt_at'] > time.time()


def test_apns_jwt_uses_team_and_key_identifier(setup, tmp_path):
    import jwt
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import serialization
    _, app, _, store, _, _ = setup
    key = ec.generate_private_key(ec.SECP256R1())
    path = tmp_path / 'key.p8'
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                                      serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    settings = replace(app.state.service.delivery.settings, apns_key_path=str(path),
                       apns_key_id='APPLEKEY', apns_team_id='APPLETEAM', apns_bundle_id='com.example.capa')
    delivery = Delivery(settings, store)
    token = delivery.authorization().split(' ', 1)[1]
    assert jwt.get_unverified_header(token)['kid'] == 'APPLEKEY'
    claims = jwt.decode(token, key.public_key(), algorithms=['ES256'])
    assert claims['iss'] == 'APPLETEAM'
    assert abs(time.time() - claims['iat']) < 5


def test_resolved_clarification_is_not_announced_later(setup):
    http, app, server, store, headers, _ = setup
    submit(http, headers)
    server.runs['run-1'] = {'status': 'waiting_for_approval', 'pending_controls': [{
        'kind': 'clarification', 'prompt_id': 'p1', 'execution_generation': 1, 'question': 'Which region?'}]}
    asyncio.run(app.state.service.reconcile())
    assert len(store.events()) == 1
    server.runs['run-1'] = {'status': 'running', 'pending_controls': []}
    asyncio.run(app.state.service.reconcile())
    assert store.events() == []
