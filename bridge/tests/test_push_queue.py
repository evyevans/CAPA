import asyncio
import time

import httpx

from test_bridge import setup, submit
from test_delivery import make_delivery


def test_only_one_unacknowledged_ptt_update_is_dispatched_per_device(setup):
    http, app, _, store, headers, paired = setup
    task = submit(http, headers).json()
    stored = store.task(task['id'])
    store.add_event(stored, 'completed', 'First result')
    store.add_event(stored, 'clarification', 'Second question', 'prompt-2')
    http.put('/v1/workspace', headers=headers, json={'reply_mode': 'spoken'})
    http.put('/v1/device', headers=headers, json={'available': True, 'ptt_token': 'aabb',
                                                'notification_token': 'ccdd', 'channel_id': 'channel'})
    sent = []
    def handle(request):
        sent.append(request)
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    asyncio.run(delivery.flush())
    assert len(sent) == 1
    first = store.events()[0]
    store.update_event(first['id'], acknowledged=1)
    asyncio.run(delivery.flush())
    assert len(sent) == 2


def test_ended_channel_falls_back_without_replaying_speech(setup):
    http, app, _, store, headers, _ = setup
    task = submit(http, headers).json()
    store.add_event(store.task(task['id']), 'completed', 'Result')
    http.put('/v1/workspace', headers=headers, json={'reply_mode': 'spoken'})
    http.put('/v1/device', headers=headers, json={'available': True, 'ptt_token': 'aabb',
                                                'notification_token': 'ccdd', 'channel_id': 'channel'})
    sent = []
    def handle(request):
        sent.append(request)
        if request.headers['apns-push-type'] == 'pushtotalk':
            return httpx.Response(410, json={'reason': 'Unregistered'})
        return httpx.Response(200)
    delivery = make_delivery(app, store, handle)
    asyncio.run(delivery.flush())
    assert [r.headers['apns-push-type'] for r in sent] == ['pushtotalk', 'alert']
    assert store.events()[0]['notified']
    assert not store.events()[0]['acknowledged']
