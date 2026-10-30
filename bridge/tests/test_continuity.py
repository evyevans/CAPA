import asyncio
import sqlite3
import time
import uuid
from test_bridge import setup, submit


def linked_device(http, headers):
    invitation = http.post('/v1/devices/link', headers=headers)
    assert invitation.status_code == 200
    result = http.post('/v1/pair', json={'code': invitation.json()['code'], 'name': 'My Mac'})
    assert result.status_code == 200
    pair = result.json()
    return {'Authorization': f"Bearer {pair['token']}"}, pair


def test_linked_devices_share_identity_task_session_and_idempotency(setup):
    http, _, server, store, phone, original = setup
    mac, linked = linked_device(http, phone)
    first = submit(http, phone).json()
    second = submit(http, mac).json()
    assert first['id'] == second['id']
    assert len(server.creations) == 1
    assert http.get('/v1/me', headers=phone).json()['workspace_id'] == http.get('/v1/me', headers=mac).json()['workspace_id']
    assert store.device(original['device_id'])['session_id'] == store.device(linked['device_id'])['session_id']
    assert http.get('/v1/tasks', headers=mac).json()[0]['id'] == first['id']
    assert http.get(f"/v1/tasks/{first['id']}", headers=mac).status_code == 200


def test_linked_device_can_resolve_current_clarification(setup):
    http, _, server, _, phone, _ = setup
    mac, _ = linked_device(http, phone)
    task = submit(http, phone).json()
    server.runs['run-1'] = {'status': 'waiting_for_approval', 'pending_controls': [{
        'kind': 'clarify', 'prompt_id': 'p1', 'execution_generation': 4, 'question': 'Which region?'}]}
    response = http.post(f"/v1/tasks/{task['id']}/control", headers=mac, json={
        'request_id': 'p1', 'execution_generation': 4, 'answer': 'Canada'})
    assert response.status_code == 200
    assert len(server.creations) == 1
    assert server.controls[-1][0] == '/v1/runs/run-1/clarify'


def test_notification_first_defaults_and_explicit_device_handoff(setup):
    http, app, server, store, phone, original = setup
    mac, linked = linked_device(http, phone)
    assert http.get('/v1/me', headers=phone).json()['reply_mode'] == 'notifications'
    assert http.put('/v1/workspace', headers=mac, json={
        'reply_mode': 'spoken', 'preferred_device_id': linked['device_id']}).status_code == 200
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Research done.'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=phone).json()[0]
    assert event['delivery_device_id'] == linked['device_id']
    assert http.get('/v1/events', headers=mac).json()[0]['id'] == event['id']
    assert store.workspace_for(original['device_id'])['preferred_device_id'] == linked['device_id']


def test_playback_claim_prevents_two_devices_speaking_same_update(setup):
    http, app, server, _, phone, _ = setup
    mac, _ = linked_device(http, phone)
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Complete.'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=mac).json()[0]
    path = f"/v1/events/{event['id']}"
    token = str(uuid.uuid4())
    assert http.post(path + '/claim', headers=mac, json={'token': token, 'manual': True}).status_code == 200
    assert http.post(path + '/claim', headers=phone, json={'token': str(uuid.uuid4()), 'manual': True}).status_code == 409
    assert http.post(path + '/ack', headers=phone, json={'token': token}).status_code == 409
    assert http.post(path + '/ack', headers=mac, json={'token': token}).status_code == 200
    assert http.post(path + '/ack', headers=mac, json={'token': token}).status_code == 200
    assert http.get('/v1/events', headers=phone).json() == []


def test_revoked_origin_does_not_abandon_task_and_cannot_access_linked_account(setup):
    http, app, server, _, phone, original = setup
    mac, _ = linked_device(http, phone)
    submit(http, phone)
    assert http.delete(f"/v1/devices/{original['device_id']}", headers=mac).status_code == 200
    server.runs['run-1'] = {'status': 'completed', 'output': 'Preserved result'}
    asyncio.run(app.state.service.reconcile())
    assert http.get('/v1/tasks', headers=mac).json()[0]['output'] == 'Preserved result'
    assert http.get('/v1/tasks', headers=phone).status_code == 401
    assert http.post('/v1/devices/link', headers=phone).status_code == 401


def test_foreign_workspace_cannot_link_revoke_route_or_claim(setup):
    http, _, _, store, phone, original = setup
    other = http.post('/v1/pair', json={'code': store.issue_pairing_code(), 'name': 'Separate'}).json()
    foreign = {'Authorization': f"Bearer {other['token']}"}
    assert http.delete(f"/v1/devices/{original['device_id']}", headers=foreign).status_code == 404
    assert http.put('/v1/workspace', headers=foreign, json={'preferred_device_id': original['device_id']}).status_code == 422
    assert http.get('/v1/devices', headers=foreign).json()[0]['id'] == other['device_id']


def test_existing_database_migrates_without_merging_devices_or_changing_sessions(tmp_path):
    from capa_bridge.store import Store, digest
    path = tmp_path / 'old.sqlite3'
    with sqlite3.connect(path) as db:
        db.executescript('''CREATE TABLE devices (id TEXT PRIMARY KEY,name TEXT NOT NULL,token_hash TEXT UNIQUE NOT NULL,
        session_id TEXT NOT NULL,revoked INTEGER NOT NULL DEFAULT 0, available INTEGER NOT NULL DEFAULT 0,
        ptt_token TEXT,notification_token TEXT,channel_id TEXT);
        CREATE TABLE pairing_codes (hash TEXT PRIMARY KEY,expires_at REAL NOT NULL);''')
        for number in [1, 2]:
            db.execute('INSERT INTO devices (id,name,token_hash,session_id) VALUES (?,?,?,?)',
                       (f'd{number}', f'Device {number}', digest(f'token{number}'), f'capa-original{number}'))
    first = Store(path)
    second = Store(path)
    assert first.workspace_for('d1')['id'] != first.workspace_for('d2')['id']
    assert first.authenticate('token1')['session_id'] == 'capa-original1'
    assert first.workspace_for('d1')['session_id'] == 'capa-original1'
    assert first.workspace_for('d1') == second.workspace_for('d1')


def test_connections_use_real_discovery_and_do_not_expose_secrets(setup):
    http, _, _, _, phone, _ = setup
    response = http.get('/v1/connections', headers=phone)
    assert response.status_code == 200
    assert response.json()['discovery_available'] is False
    assert 'hermes-secret' not in response.text


def test_discovered_connections_are_real_and_allowlisted(setup):
    import httpx
    http, app, server, _, phone, _ = setup
    original = server.handle
    def discovery(request):
        if request.url.path == '/v1/capabilities':
            return httpx.Response(200, json={'endpoints': {'toolsets': {}, 'skills': {}}})
        return original(request)
    # Real capabilities advertise nonempty method/path descriptors.
    def available(request):
        if request.url.path == '/v1/capabilities':
            return httpx.Response(200, json={'endpoints': {
                'toolsets': {'method': 'GET', 'path': '/v1/toolsets'},
                'skills': {'method': 'GET', 'path': '/v1/skills'}}})
        if request.url.path == '/v1/toolsets':
            return httpx.Response(200, json=[{'name': 'calendar', 'label': 'Calendar',
                'enabled': True, 'configured': False, 'tools': ['calendar_read'], 'api_key': 'never-forward'}])
        if request.url.path == '/v1/skills':
            return httpx.Response(200, json=[{'name': 'research', 'description': 'Research brief', 'secret': 'private'}])
        return original(request)
    app.state.service.hermes.client._transport = httpx.MockTransport(available)
    result = http.get('/v1/connections', headers=phone)
    assert result.json()['discovery_available']
    assert result.json()['toolsets'][0]['configured'] is False
    assert result.json()['skills'][0]['name'] == 'research'
    assert 'never-forward' not in result.text and 'private' not in result.text


def test_revoking_issuer_invalidates_unused_invitation(setup):
    http, _, _, store, phone, original = setup
    code = http.post('/v1/devices/link', headers=phone).json()['code']
    store.revoke_device(original['device_id'])
    assert http.post('/v1/pair', json={'code': code, 'name': 'Untrusted'}).status_code == 401


def test_stale_playback_receipt_cannot_ack_a_new_claim(setup):
    import time
    http, app, server, store, phone, _ = setup
    mac, linked = linked_device(http, phone)
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Result'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=phone).json()[0]
    path = f"/v1/events/{event['id']}"
    old, new = str(uuid.uuid4()), str(uuid.uuid4())
    assert http.post(path + '/claim', headers=phone, json={'token': old, 'manual': True}).status_code == 200
    with store.connect() as db:
        db.execute('UPDATE events SET lease_expires_at=? WHERE id=?', (time.time() - 1, event['id']))
    assert http.post(path + '/claim', headers=mac, json={'token': new, 'manual': True}).status_code == 200
    assert http.post(path + '/ack', headers=phone, json={'token': old}).status_code == 409
    assert 'lease_token_hash' not in http.get(path, headers=mac).json()


def test_automatic_claim_requires_selected_device_and_spoken_mode(setup):
    http, app, server, _, phone, original = setup
    mac, linked = linked_device(http, phone)
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Result'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=phone).json()[0]
    path = f"/v1/events/{event['id']}/claim"
    http.put('/v1/device', headers=mac, json={'available': True})
    assert http.post(path, headers=mac, json={'token': str(uuid.uuid4())}).status_code == 409
    http.put('/v1/workspace', headers=mac, json={'reply_mode': 'spoken', 'preferred_device_id': linked['device_id']})
    assert http.post(path, headers=phone, json={'token': str(uuid.uuid4())}).status_code == 409
    assert http.post(path, headers=mac, json={'token': str(uuid.uuid4())}).status_code == 200


def test_in_flight_push_cannot_speak_after_switching_destination(setup):
    http, app, server, store, phone, original = setup
    mac, linked = linked_device(http, phone)
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Result'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=phone).json()[0]
    http.put('/v1/device', headers=phone, json={'available': True})
    http.put('/v1/workspace', headers=phone, json={'reply_mode': 'spoken'})
    store.update_event(event['id'], ptt_sent_at=time.time())
    http.put('/v1/workspace', headers=mac, json={'preferred_device_id': linked['device_id']})
    response = http.post(f"/v1/events/{event['id']}/claim", headers=phone,
                         json={'token': str(uuid.uuid4()), 'manual': False})
    assert response.status_code == 409
    assert http.get('/v1/events', headers=mac).json()[0]['delivery_device_id'] == linked['device_id']


def test_revoking_destination_preserves_lease_but_routes_pending_result_to_survivor(setup):
    http, app, server, store, phone, original = setup
    mac, linked = linked_device(http, phone)
    submit(http, phone)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Result'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=phone).json()[0]
    path = f"/v1/events/{event['id']}/claim"
    assert http.post(path, headers=phone, json={'token': str(uuid.uuid4()), 'manual': True}).status_code == 200
    store.update_event(event['id'], ptt_sent_at=time.time())
    http.delete(f"/v1/devices/{original['device_id']}", headers=mac)
    pending = http.get('/v1/events', headers=mac).json()[0]
    assert pending['delivery_device_id'] == linked['device_id']
    assert pending['ptt_sent_at'] is None
    assert http.post(path, headers=mac, json={'token': str(uuid.uuid4()), 'manual': True}).status_code == 409
    with store.connect() as db:
        db.execute('UPDATE events SET lease_expires_at=0 WHERE id=?', (event['id'],))
    assert http.post(path, headers=mac, json={'token': str(uuid.uuid4()), 'manual': True}).status_code == 200


def test_old_push_success_does_not_mark_new_destination_notified(setup):
    import httpx
    from test_delivery import event_for, make_delivery
    http, app, _, store, phone, original = setup
    mac, linked = linked_device(http, phone)
    event_for(setup)
    http.put('/v1/device', headers=phone, json={'notification_token': 'aabb'})
    http.put('/v1/device', headers=mac, json={'notification_token': 'ccdd'})
    sent = []
    def handle(request):
        sent.append(request.url.path)
        if len(sent) == 1:
            store.update_workspace(original['device_id'], {'preferred_device_id': linked['device_id']})
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    asyncio.run(delivery.flush())
    assert store.events()[0]['notified'] == 0
    asyncio.run(delivery.flush())
    assert sent == ['/3/device/aabb', '/3/device/ccdd']
    assert store.events()[0]['notified'] == 1


def test_current_hermes_discovery_envelope_survives_skills_endpoint_failure(setup):
    import httpx
    http, app, server, _, phone, _ = setup
    original = server.handle
    def discovery(request):
        if request.url.path == '/v1/capabilities':
            return httpx.Response(200, json={'endpoints': {'toolsets': {'path': '/v1/toolsets'}, 'skills': {'path': '/v1/skills'}}})
        if request.url.path == '/v1/toolsets':
            return httpx.Response(200, json={'object': 'list', 'platform': 'api_server', 'data': [
                {'name': 'core', 'enabled': True, 'configured': True, 'tools': ['read_file'], 'secret': 'hidden'}]})
        if request.url.path == '/v1/skills':
            return httpx.Response(500, json={'error': {'message': 'Failed to enumerate skills'}})
        return original(request)
    app.state.service.hermes.client._transport = httpx.MockTransport(discovery)
    result = http.get('/v1/connections', headers=phone)
    assert result.json()['discovery_available']
    assert result.json()['toolsets'][0]['name'] == 'core'
    assert result.json()['skills'] == []
    assert 'unavailable' in result.json()['message'].lower()
    assert 'hidden' not in result.text
