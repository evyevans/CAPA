import asyncio
import logging
import time
import httpx

logger = logging.getLogger(__name__)
TERMINAL = {'completed', 'failed', 'cancelled', 'interrupted'}


def control_identity(control):
    return control.get('prompt_id') or control.get('request_id')


def is_clarification(control):
    return control.get('kind', control.get('type', '')) in ('clarification', 'clarify')


class Service:
    def __init__(self, store, hermes, delivery=None):
        self.store, self.hermes, self.delivery = store, hermes, delivery
        self.lock = asyncio.Lock()

    async def submit(self, device, request_id, text):
        async with self.lock:
            task = self.store.reserve_task(device, request_id, text)
            if task['status'] == 'submitting':
                await self.admit(task)
            return self.store.task(task['id'])

    async def admit(self, task):
        if time.time() - task['created_at'] > 23 * 3600:
            self.store.snapshot(task, 'unknown', notices=[('unknown', 'Task acceptance could not be confirmed. '
                                 'Review Hermes before submitting this work again.', '')])
            return
        try:
            result = await self.hermes.create(task)
            run_id = result.get('run_id')
            if not isinstance(run_id, str) or not run_id:
                raise ValueError('Hermes did not return a run identifier')
            self.store.update_task(task['id'], run_id=run_id, status=result.get('status', 'started'))
        except (httpx.TransportError, httpx.HTTPStatusError) as exc:
            # A timeout can follow a committed admission. Keep its original key.
            if isinstance(exc, httpx.HTTPStatusError) and 400 <= exc.response.status_code < 500:
                self.store.snapshot(task, 'failed', notices=[('failed',
                    'Hermes refused this request. Review your configuration and permissions.', '')])
        except ValueError:
            self.store.snapshot(task, 'unknown', notices=[('unknown',
                'Hermes could not confirm task acceptance. Check API compatibility.', '')])

    async def refresh(self, task):
        result = await self.hermes.status(task['run_id'])
        status = result.get('status', 'unknown')
        controls = result.get('pending_controls') or []
        if isinstance(controls, dict):
            controls = list(controls.values())
        notices = []
        if status in TERMINAL or status == 'unknown':
            text = result.get('output') if status == 'completed' else None
            text = text or {'failed': 'Hermes could not complete the task.',
                            'cancelled': 'The task was stopped.',
                            'interrupted': 'The Hermes host interrupted this task.',
                            'unknown': 'Hermes cannot confirm the outcome. Review the task before retrying.'}.get(status,
                            'Hermes completed the task. Open CAPA for details.')
            notices.append((status, text, ''))
        for control in controls:
            identity = control_identity(control)
            if not identity or not isinstance(control.get('execution_generation'), int):
                continue
            kind = 'clarification' if is_clarification(control) else 'approval'
            text = (control.get('question') or control.get('prompt') or control.get('description') or
                    ('Hermes needs your clarification.' if kind == 'clarification' else
                     'Hermes needs your approval. Open CAPA to review the action.'))
            notices.append((kind, str(text), f"{identity}:{control['execution_generation']}"))
        self.store.snapshot(task, status, result.get('output') or '', controls, notices)

    async def reconcile(self):
        async with self.lock:
            for task in self.store.tasks(active=True):
                device = self.store.device(task['device_id'])
                if not device or not any(not d['revoked'] for d in self.store.devices(device['id'])):
                    continue
                try:
                    if not task['run_id']:
                        await self.admit(task)
                    else:
                        await self.refresh(task)
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code == 404:
                        self.store.snapshot(task, 'unknown', notices=[('unknown',
                            'Hermes no longer has this run. Review its session history; CAPA has not restarted the work.', '')])
                except (httpx.TransportError, ValueError, TypeError):
                    logger.warning('Could not reconcile task %s; retaining prior state', task['id'])
        if self.delivery:
            await self.delivery.flush()

    async def run(self, interval):
        while True:
            try:
                await self.reconcile()
            except Exception:
                # Keep polling after an isolated failure; do not log result bodies or credentials.
                logger.exception('CAPA reconciliation failed')
            await asyncio.sleep(interval)
