"""Exercise persistence and app behavior, replacing only external Hermes HTTP."""
import asyncio
import json
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from capa_bridge.app import create_app
from capa_bridge.config import Settings
from capa_bridge.store import Store


class HermesServer:
    def __init__(self):
        self.creations = []
        self.controls = []
        self.runs = {}
        self.fail_submission = False

    def handle(self, request):
        assert request.headers['authorization'] == 'Bearer hermes-secret'
        path = request.url.path
        if path == '/v1/capabilities':
            return httpx.Response(200, json={'features': {
                'run_status': True, 'run_approval_response': True,
                'run_stop': True}, 'endpoints': {
                'runs': {'method': 'POST', 'path': '/v1/runs'},
                'run_status': {'method': 'GET', 'path': '/v1/runs/{run_id}'},
                'run_approval': {'method': 'POST', 'path': '/v1/runs/{run_id}/approval'},
                'run_stop': {'method': 'POST', 'path': '/v1/runs/{run_id}/stop'}}})
        if path == '/v1/runs' and request.method == 'POST':
            key = request.headers['idempotency-key']
            self.creations.append((key, json.loads(request.content)))
            # Model a committed Hermes admission whose HTTP response was lost.
            if self.fail_submission:
                self.fail_submission = False
                raise httpx.ReadTimeout('response lost', request=request)
            return httpx.Response(202, json={'run_id': 'run-1', 'status': 'started'})
        if path == '/v1/runs/run-1' and request.method == 'GET':
            return httpx.Response(200, json=self.runs.get('run-1', {
                'run_id': 'run-1', 'status': 'running'}))
        if request.method == 'POST':
            self.controls.append((path, json.loads(request.content)))
            return httpx.Response(200, json={'status': 'stopping' if path.endswith('/stop') else 'running'})
        return httpx.Response(404, json={'error': 'not found'})


@pytest.fixture
def setup(tmp_path):
    settings = Settings(database=tmp_path / 'capa.sqlite3', hermes_url='http://127.0.0.1:8642',
                        hermes_key='hermes-secret', poll_seconds=3600)
    server = HermesServer()
    store = Store(settings.database)
    code = store.issue_pairing_code()
    client = httpx.AsyncClient(transport=httpx.MockTransport(server.handle), base_url=settings.hermes_url)
    app = create_app(settings, store=store, hermes_client=client, start_worker=False)
    with TestClient(app) as http:
        response = http.post('/v1/pair', json={'code': code, 'name': 'Evy iPhone'})
        assert response.status_code == 200
        paired = response.json()
        headers = {'Authorization': f"Bearer {paired['token']}"}
        yield http, app, server, store, headers, paired


def submit(http, headers, key='memo-1', text='Research three sources on batteries'):
    return http.post('/v1/tasks', headers=headers, json={'request_id': key, 'text': text})


def test_pairing_code_is_one_use_and_device_can_be_revoked(setup):
    http, _, _, store, headers, paired = setup
    code = store.issue_pairing_code()
    assert http.post('/v1/pair', json={'code': code, 'name': 'Other'}).status_code == 200
    assert http.post('/v1/pair', json={'code': code, 'name': 'Other'}).status_code == 401
    assert http.get('/v1/tasks', headers=headers).status_code == 200
    assert store.revoke_device(paired['device_id'])
    assert http.get('/v1/tasks', headers=headers).status_code == 401


def test_expired_pairing_and_unauthenticated_access_are_refused(setup):
    http, _, _, store, _, _ = setup
    code = store.issue_pairing_code(ttl=-1)
    assert http.post('/v1/pair', json={'code': code, 'name': 'Phone'}).status_code == 401
    assert http.get('/v1/tasks').status_code == 401
    assert http.get('/v1/tasks', headers={'Authorization': 'Bearer invalid'}).status_code == 401


def test_pairing_credential_is_hashed_at_rest(setup):
    _, _, _, store, _, paired = setup
    with store.connect() as db:
        row = db.execute('SELECT token_hash FROM devices WHERE id=?', (paired['device_id'],)).fetchone()
        assert paired['token'] not in row['token_hash']


def test_duplicate_memo_reuses_one_hermes_admission_and_session(setup):
    http, _, server, _, headers, _ = setup
    first = submit(http, headers)
    assert first.status_code == 202
    assert first.json()['status'] == 'started'
    second = submit(http, headers)
    assert second.json()['id'] == first.json()['id']
    assert len(server.creations) == 1
    assert server.creations[0][1]['session_id'].startswith('capa-')
    assert submit(http, headers, text='Different work').status_code == 409


def test_lost_submission_response_retries_same_key_without_false_ack(setup):
    http, _, server, _, headers, _ = setup
    server.fail_submission = True
    first = submit(http, headers)
    assert first.status_code == 202
    assert first.json()['status'] == 'submitting'
    second = submit(http, headers)
    assert second.json()['status'] == 'started'
    assert server.creations[0] == server.creations[1]


def test_results_survive_restart_and_playback_ack_does_not_repeat(setup):
    http, app, server, store, headers, paired = setup
    task = submit(http, headers).json()
    server.runs['run-1'] = {'run_id': 'run-1', 'status': 'completed',
                            'output': 'Three useful findings.\n\nSources:\nhttps://example.org/research'}
    asyncio.run(app.state.service.reconcile())
    asyncio.run(app.state.service.reconcile())
    events = http.get('/v1/events', headers=headers).json()
    assert len(events) == 1
    assert events[0]['kind'] == 'completed'
    assert 'https://example.org/research' in http.get(f"/v1/tasks/{task['id']}", headers=headers).json()['output']
    reopened = Store(store.path)
    assert len(reopened.events(paired['device_id'])) == 1
    event_id = events[0]['id']
    assert http.post(f'/v1/events/{event_id}/ack', headers=headers).status_code == 200
    assert http.post(f'/v1/events/{event_id}/ack', headers=headers).status_code == 200
    assert http.get('/v1/events', headers=headers).json() == []


def test_availability_off_discards_ptt_token_but_keeps_results(setup):
    http, _, _, store, headers, paired = setup
    assert http.put('/v1/device', headers=headers, json={
        'available': True, 'ptt_token': 'aabb', 'channel_id': 'channel',
        'notification_token': 'ccdd'}).status_code == 200
    assert store.device(paired['device_id'])['ptt_token'] == 'aabb'
    assert http.put('/v1/device', headers=headers, json={'available': False}).status_code == 200
    device = store.device(paired['device_id'])
    assert device['ptt_token'] is None
    assert not device['available']
    assert device['notification_token'] == 'ccdd'


def test_other_device_cannot_read_ack_or_control_tasks(setup):
    http, app, server, store, headers, _ = setup
    task = submit(http, headers).json()
    code = store.issue_pairing_code()
    other = http.post('/v1/pair', json={'code': code, 'name': 'Other'}).json()
    other_headers = {'Authorization': f"Bearer {other['token']}"}
    server.runs['run-1'] = {'status': 'completed', 'output': 'Private result'}
    asyncio.run(app.state.service.reconcile())
    event = http.get('/v1/events', headers=headers).json()[0]
    assert http.get(f"/v1/tasks/{task['id']}", headers=other_headers).status_code == 404
    assert http.get(f"/v1/events/{event['id']}", headers=other_headers).status_code == 404
    assert http.post(f"/v1/events/{event['id']}/ack", headers=other_headers).status_code == 404
    assert http.post(f"/v1/tasks/{task['id']}/stop", headers=other_headers).status_code == 404


def test_clarification_identity_and_stale_approval_are_enforced(setup):
    http, app, server, _, headers, _ = setup
    task = submit(http, headers).json()
    server.runs['run-1'] = {'status': 'waiting_for_approval', 'pending_controls': [{
        'kind': 'clarify', 'prompt_id': 'prompt-2', 'execution_generation': 3,
        'question': 'Which region?'}]}
    asyncio.run(app.state.service.reconcile())
    events = http.get('/v1/events', headers=headers).json()
    assert events[0]['kind'] == 'clarification'
    path = f"/v1/tasks/{task['id']}/control"
    assert http.post(path, headers=headers, json={
        'request_id': 'old', 'execution_generation': 3, 'answer': 'Canada'}).status_code == 409
    assert server.controls == []
    assert http.post(path, headers=headers, json={
        'request_id': 'prompt-2', 'execution_generation': 3, 'answer': 'Canada'}).status_code == 200
    assert server.controls[-1] == ('/v1/runs/run-1/clarify', {
        'request_id': 'prompt-2', 'execution_generation': 3, 'answer': 'Canada'})


def test_ambiguous_admission_after_retention_window_is_not_replayed(setup):
    http, app, server, store, headers, _ = setup
    server.fail_submission = True
    task = submit(http, headers).json()
    with store.connect() as db:
        db.execute('UPDATE tasks SET created_at=? WHERE id=?', (time.time() - 86401, task['id']))
    asyncio.run(app.state.service.reconcile())
    assert len(server.creations) == 1
    assert http.get(f"/v1/tasks/{task['id']}", headers=headers).json()['status'] == 'unknown'


def test_empty_and_oversized_memos_are_rejected(setup):
    http, _, server, _, headers, _ = setup
    assert submit(http, headers, text='   ').status_code == 422
    assert submit(http, headers, text='x' * 20001).status_code == 422
    assert server.creations == []
