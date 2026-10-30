import asyncio
from contextlib import asynccontextmanager, suppress
from collections import defaultdict, deque
import time
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
import httpx

from .config import Settings
from .hermes import Hermes
from .service import Service, control_identity, is_clarification
from .store import Store
from .speech import Speech, SpeechUnavailable


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Pair(StrictModel):
    code: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)
    platform: str = Field(default='ios', pattern=r'^(ios|macos|android|windows|linux)$')


class WorkspaceUpdate(StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    reply_mode: str | None = Field(default=None, pattern=r'^(notifications|spoken)$')
    preferred_device_id: str | None = Field(default=None, min_length=1, max_length=100)

    @field_validator('name', 'reply_mode', 'preferred_device_id')
    @classmethod
    def supplied_value(cls, value):
        if value is None or not value.strip():
            raise ValueError('Supply a nonempty value')
        return value.strip()


class PlaybackClaim(StrictModel):
    token: str = Field(min_length=36, max_length=36, pattern=r'^[0-9a-fA-F-]+$')
    manual: bool = False


class PlaybackReceipt(StrictModel):
    token: str | None = Field(default=None, min_length=36, max_length=36)


class Memo(StrictModel):
    request_id: str = Field(min_length=1, max_length=128, pattern=r'^[a-zA-Z0-9_-]+$')
    text: str = Field(min_length=1, max_length=20000)

    @field_validator('text')
    @classmethod
    def nonempty(cls, value):
        if not value.strip():
            raise ValueError('Speak or enter a request first')
        return value.strip()


class DeviceUpdate(StrictModel):
    available: bool | None = None
    ptt_token: str | None = Field(default=None, max_length=512, pattern=r'^[a-fA-F0-9]+$')
    notification_token: str | None = Field(default=None, max_length=512, pattern=r'^[a-fA-F0-9]+$')
    channel_id: str | None = Field(default=None, max_length=100)

    @field_validator('available')
    @classmethod
    def nonnull_availability(cls, value):
        if value is None:
            raise ValueError('Availability must be true or false when supplied')
        return value


class Control(StrictModel):
    request_id: str = Field(min_length=1, max_length=200)
    execution_generation: int = Field(ge=0, strict=True)
    answer: str | None = Field(default=None, min_length=1, max_length=10000)
    choice: str | None = Field(default=None, pattern=r'^(once|deny)$')


def public_task(task):
    return {k: v for k, v in task.items() if k not in ('payload', 'device_id', 'request_id')}


def public_event(event):
    return {k: v for k, v in event.items() if k != 'lease_token_hash'}


def create_app(settings: Settings, *, store=None, hermes_client=None, start_worker=True, delivery=None):
    store = store or Store(settings.database)
    hermes = Hermes(settings, hermes_client)
    if delivery is None:
        from .delivery import Delivery
        delivery = Delivery(settings, store)
    service = Service(store, hermes, delivery)
    speech = Speech(settings)
    delivery.speech = speech

    @asynccontextmanager
    async def lifespan(app):
        worker = asyncio.create_task(service.run(settings.poll_seconds)) if start_worker else None
        yield
        if worker:
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker
        await hermes.client.aclose()
        await delivery.close()

    app = FastAPI(title='CAPA private bridge', version='0.1.0', lifespan=lifespan,
                  docs_url=None, redoc_url=None)
    app.state.service = service
    app.state.store = store
    attempts = defaultdict(deque)

    @app.middleware('http')
    async def private_responses(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response

    def authenticate(authorization: Annotated[str | None, Header()] = None):
        if not authorization or not authorization.startswith('Bearer '):
            raise HTTPException(401, 'Pair this device first')
        device = store.authenticate(authorization[7:])
        if not device:
            raise HTTPException(401, 'Device credential is invalid or revoked')
        return device

    Device = Annotated[dict, Depends(authenticate)]

    def owned_task(task_id, device):
        task = store.task(task_id, device['id'])
        if not task:
            raise HTTPException(404, 'Task not found')
        return task

    def owned_event(event_id, device):
        event = store.event(event_id, device['id'])
        if not event:
            raise HTTPException(404, 'Update not found')
        return event

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.post('/v1/pair')
    def pair(body: Pair, request: Request):
        host = request.client.host if request.client else 'unknown'
        now = time.monotonic()
        # Bound the limiter's memory without trusting forwarded IP headers.
        if len(attempts) > 1000:
            for key in list(attempts):
                if not attempts[key] or now - attempts[key][-1] > 60:
                    del attempts[key]
        recent = attempts[host]
        while recent and now - recent[0] > 60:
            recent.popleft()
        if len(recent) >= 10:
            raise HTTPException(429, 'Wait one minute before pairing again')
        recent.append(now)
        result = store.pair(body.code, body.name, body.platform)
        if not result:
            raise HTTPException(401, 'Pairing code expired or already used')
        return result

    @app.get('/v1/me')
    def identity(device: Device):
        workspace = store.workspace_for(device['id'])
        return {'device_id': device['id'], 'workspace_id': workspace['id'],
                'name': workspace['name'], 'reply_mode': workspace['reply_mode'],
                'preferred_device_id': workspace['preferred_device_id']}

    @app.put('/v1/workspace')
    def update_workspace(body: WorkspaceUpdate, device: Device):
        try:
            store.update_workspace(device['id'], body.model_dump(exclude_unset=True))
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return identity(device)

    @app.get('/v1/devices')
    def devices(device: Device):
        return store.devices(device['id'])

    @app.post('/v1/devices/link')
    def link_device(device: Device):
        return {'code': store.issue_pairing_code(device_id=device['id']), 'expires_in': 300}

    @app.delete('/v1/devices/{device_id}')
    def revoke_linked_device(device_id: str, device: Device):
        if not any(d['id'] == device_id for d in store.devices(device['id'])):
            raise HTTPException(404, 'Device not found')
        store.revoke_device(device_id)
        return {'revoked': True}

    @app.get('/v1/connections')
    async def connections(device: Device):
        try:
            return await hermes.connections()
        except (httpx.HTTPError, ValueError):
            return {'discovery_available': False, 'toolsets': [], 'skills': [],
                    'message': 'Hermes discovery is unavailable. Configure tools in your Hermes installation.'}

    @app.get('/v1/capabilities')
    async def capabilities(device: Device):
        try:
            return {'hermes': await hermes.capabilities(), 'push_configured': delivery.configured,
                    'host_speech': bool(settings.hermes_python and settings.hermes_repository)}
        except httpx.HTTPError:
            raise HTTPException(503, 'Hermes is unavailable')

    @app.put('/v1/device')
    def update_device(body: DeviceUpdate, device: Device):
        store.update_device(device['id'], body.model_dump(exclude_unset=True))
        return {'available': bool(store.device(device['id'])['available'])}

    @app.delete('/v1/device')
    def revoke(device: Device):
        store.revoke_device(device['id'])
        return {'revoked': True}

    @app.post('/v1/tasks', status_code=202)
    async def submit(body: Memo, device: Device):
        try:
            return public_task(await service.submit(device, body.request_id, body.text))
        except ValueError as exc:
            raise HTTPException(409, str(exc))

    @app.get('/v1/tasks')
    def tasks(device: Device):
        return [public_task(t) for t in store.tasks(device['id'])]

    @app.get('/v1/tasks/{task_id}')
    def task(task_id: str, device: Device):
        return public_task(owned_task(task_id, device))

    @app.get('/v1/metrics')
    def metrics(device: Device):
        tasks = store.tasks(device['id'])
        events = store.events(device['id'], pending=False)
        results = [e for e in events if e['kind'] not in ('approval', 'clarification')]
        return {
            'submitted_tasks': len(tasks),
            'accepted_tasks': sum(t['run_id'] is not None for t in tasks),
            'unconfirmed_tasks': sum(t['status'] in ('submitting', 'unknown') for t in tasks),
            'completed_tasks': sum(t['status'] == 'completed' for t in tasks),
            'pending_updates': sum(not e['acknowledged'] for e in events),
            'notified_updates': sum(bool(e['notified']) for e in results),
            'acknowledged_updates': sum(bool(e['acknowledged']) for e in results),
        }

    @app.get('/v1/events')
    def events(device: Device):
        return [public_event(e) for e in store.events(device['id'])]

    @app.get('/v1/events/{event_id}')
    def event(event_id: str, device: Device):
        return public_event(owned_event(event_id, device))

    @app.post('/v1/events/{event_id}/claim')
    def claim(event_id: str, body: PlaybackClaim, device: Device):
        owned_event(event_id, device)
        try:
            store.claim(event_id, device['id'], body.token, body.manual)
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {'claimed': True, 'expires_in': 120}

    @app.post('/v1/events/{event_id}/ack')
    def ack(event_id: str, device: Device, body: PlaybackReceipt | None = None):
        owned_event(event_id, device)
        try:
            store.acknowledge(event_id, device['id'], body.token if body else None)
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {'acknowledged': True}

    @app.post('/v1/transcribe')
    async def transcribe(request: Request, device: Device):
        if not speech.configured:
            raise HTTPException(503, 'Host speech is not configured')
        if request.headers.get('content-type', '').split(';')[0] != 'audio/mp4':
            raise HTTPException(415, 'Send an M4A audio memo')
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > 8 * 1024 * 1024:
                raise HTTPException(413, 'Audio memo exceeds 8 MB')
            chunks.append(chunk)
        if not size:
            raise HTTPException(422, 'No audio received')
        try:
            return {'text': await speech.transcribe(b''.join(chunks))}
        except (SpeechUnavailable, OSError, TimeoutError):
            raise HTTPException(503, 'Hermes speech is unavailable; recording can be retried')

    @app.post('/v1/events/{event_id}/audio')
    async def audio(event_id: str, device: Device):
        event = owned_event(event_id, device)
        try:
            data = await speech.audio(event)
            return Response(content=data, media_type='audio/mpeg')
        except (SpeechUnavailable, OSError, TimeoutError):
            raise HTTPException(503, 'Host voice is unavailable; use device speech')

    async def call_control(task, action, body):
        if not task['run_id']:
            raise HTTPException(409, 'Hermes acceptance is not yet confirmed')
        try:
            return await hermes.control(task['run_id'], action, body)
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        except httpx.HTTPStatusError as exc:
            code = exc.response.status_code
            raise HTTPException(code if code in (400, 403, 404, 409, 503) else 502,
                                'Hermes refused this control; refresh the task')
        except httpx.TransportError:
            raise HTTPException(503, 'Control response unavailable; refresh before retrying')

    @app.post('/v1/tasks/{task_id}/stop')
    async def stop(task_id: str, device: Device):
        return await call_control(owned_task(task_id, device), 'stop', {})

    @app.post('/v1/tasks/{task_id}/control')
    async def control(task_id: str, body: Control, device: Device):
        task = owned_task(task_id, device)
        if not task['run_id']:
            raise HTTPException(409, 'No accepted run')
        try:
            await service.refresh(task)
        except httpx.HTTPError:
            raise HTTPException(503, 'Cannot verify the current request')
        task = store.task(task_id)
        current = next((c for c in task['controls'] if control_identity(c) == body.request_id and
                        c.get('execution_generation') == body.execution_generation), None)
        if not current:
            raise HTTPException(409, 'This request is no longer current')
        clarification = is_clarification(current)
        if (clarification and (body.answer is None or body.choice is not None)) or (
                not clarification and (body.choice is None or body.answer is not None)):
            raise HTTPException(422, 'Provide an answer for clarification or a decision for approval')
        if not clarification and body.choice not in current.get('choices', []):
            raise HTTPException(422, 'Hermes does not permit that approval choice')
        result = await call_control(task, 'clarify' if clarification else 'approval',
                                    body.model_dump(exclude_none=True))
        return result

    return app
