import asyncio
import sqlite3

import pytest

from test_bridge import setup, submit


def test_terminal_snapshot_and_delivery_event_commit_atomically(setup):
    http, app, server, store, headers, _ = setup
    task = submit(http, headers).json()
    server.runs['run-1'] = {'status': 'completed', 'output': 'Finished research.'}
    # Simulate a disk failure specifically when persisting the delivery event.
    with store.connect() as db:
        db.execute("CREATE TRIGGER fail_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
    with pytest.raises(sqlite3.IntegrityError):
        asyncio.run(app.state.service.reconcile())
    assert store.task(task['id'])['status'] == 'started'
    with store.connect() as db:
        db.execute('DROP TRIGGER fail_event')
    asyncio.run(app.state.service.reconcile())
    assert store.task(task['id'])['status'] == 'completed'
    assert len(store.events()) == 1


def test_unsupported_approval_choice_never_reaches_hermes(setup):
    http, app, server, _, headers, _ = setup
    task = submit(http, headers).json()
    server.runs['run-1'] = {'status': 'waiting_for_approval', 'pending_controls': [{
        'kind': 'approval', 'prompt_id': 'p', 'execution_generation': 1,
        'command': 'blocked command', 'description': '', 'choices': ['deny']}]}
    response = http.post(f"/v1/tasks/{task['id']}/control", headers=headers, json={
        'request_id': 'p', 'execution_generation': 1, 'choice': 'once'})
    assert response.status_code == 422
    assert server.controls == []
