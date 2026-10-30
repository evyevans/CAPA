import asyncio

from test_bridge import setup, submit


def test_metrics_distinguish_execution_push_and_playback(setup):
    http, app, server, store, headers, paired = setup
    submit(http, headers)
    server.runs['run-1'] = {'status': 'completed', 'output': 'Research complete.'}
    asyncio.run(app.state.service.reconcile())
    event = store.events()[0]
    store.update_event(event['id'], notified=1)
    before = http.get('/v1/metrics', headers=headers)
    assert before.status_code == 200
    assert before.json()['accepted_tasks'] == 1
    assert before.json()['completed_tasks'] == 1
    assert before.json()['notified_updates'] == 1
    assert before.json()['acknowledged_updates'] == 0
    http.post(f"/v1/events/{event['id']}/ack", headers=headers)
    assert http.get('/v1/metrics', headers=headers).json()['acknowledged_updates'] == 1
    other = http.post('/v1/pair', json={'code': store.issue_pairing_code(), 'name': 'Other'}).json()
    assert http.get('/v1/metrics', headers={'Authorization': f"Bearer {other['token']}"}).json()['accepted_tasks'] == 0
