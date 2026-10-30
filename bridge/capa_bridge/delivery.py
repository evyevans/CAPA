"""Delivery is separate from execution; APNs success never acknowledges playback."""
import time
from pathlib import Path
import httpx
import jwt


class Delivery:
    def __init__(self, settings, store, client=None):
        self.settings, self.store = settings, store
        self.configured = bool(settings.apns_key_path and settings.apns_key_id and
                               settings.apns_team_id and settings.apns_bundle_id)
        self.client = client or httpx.AsyncClient(http2=True, timeout=15)
        self.jwt_token = None
        self.jwt_issued_at = 0
        self.speech = None

    async def close(self):
        await self.client.aclose()

    def authorization(self):
        now = int(time.time())
        if not self.jwt_token or now - self.jwt_issued_at > 3000:
            key = Path(self.settings.apns_key_path).expanduser().read_text()
            self.jwt_token = jwt.encode({'iss': self.settings.apns_team_id, 'iat': now}, key,
                                         algorithm='ES256', headers={'kid': self.settings.apns_key_id})
            self.jwt_issued_at = now
        return f'bearer {self.jwt_token}'

    async def send(self, device, event, ptt):
        token = device['ptt_token'] if ptt else device['notification_token']
        if not token:
            return False
        host = 'api.sandbox.push.apple.com' if self.settings.apns_sandbox else 'api.push.apple.com'
        payload = ({'activeSpeaker': 'Hermes', 'event_id': event['id'], 'channel_id': device['channel_id']}
                   if ptt else {'aps': {'alert': {'title': 'CAPA', 'body': 'Hermes has an update for you.'},
                                       'sound': 'default', 'category': 'CAPA_UPDATE'}, 'event_id': event['id']})
        response = await self.client.post(f'https://{host}/3/device/{token}', json=payload, headers={
            'authorization': self.authorization(),
            'apns-topic': self.settings.apns_bundle_id + ('.voip-ptt' if ptt else ''),
            'apns-push-type': 'pushtotalk' if ptt else 'alert', 'apns-priority': '10',
            'apns-expiration': '0' if ptt else str(int(time.time()) + 3600),
            'apns-collapse-id': event['id'],
        })
        if response.status_code in (400, 410):
            try:
                invalid = response.json().get('reason') in ('BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic')
            except ValueError:
                invalid = False
            if invalid:
                self.store.update_device(device['id'], {'ptt_token' if ptt else 'notification_token': None})
        response.raise_for_status()
        return True

    async def flush(self):
        if not self.configured:
            return
        events = self.store.events()
        in_flight = {e['delivery_device_id'] for e in events if e['ptt_sent_at'] and
                     not e['notified'] and time.time() - e['ptt_sent_at'] < 45}
        for event in events:
            if event['notified'] or event['next_attempt_at'] > time.time() or event['lease_expires_at'] > time.time():
                continue
            device = self.store.device(event['delivery_device_id'])
            if not device or device['revoked']:
                continue
            workspace = self.store.workspace_for(device['id'])
            ptt = bool(workspace['reply_mode'] == 'spoken' and device['available'] and device['ptt_token'] and device['channel_id'])
            if event['ptt_sent_at']:
                if time.time() - event['ptt_sent_at'] < 45:
                    continue
                ptt = False  # No playback acknowledgment: send an ordinary alert, not another utterance.
            elif ptt and device['id'] in in_flight:
                continue
            if ptt and self.speech and self.speech.configured:
                from .speech import SpeechUnavailable
                try:
                    # Prepare before waking the phone, avoiding a long silent wait
                    # inside its system-granted receive-audio session.
                    await self.speech.audio(event)
                except (SpeechUnavailable, OSError, TimeoutError):
                    pass  # The phone can still use its native voice.
                # Opt-out/revocation may have occurred while synthesis was running.
                device = self.store.device(device['id'])
                latest = self.store.event(event['id'], device['id'])
                if (device['revoked'] or not latest or latest['acknowledged'] or
                        latest['delivery_device_id'] != device['id'] or latest['lease_expires_at'] > time.time()):
                    continue
                workspace = self.store.workspace_for(device['id'])
                ptt = bool(workspace['reply_mode'] == 'spoken' and device['available'] and device['ptt_token'] and device['channel_id'])
            try:
                if await self.send(device, event, ptt):
                    self.store.update_event(event['id'], expected_delivery_id=device['id'], **({'ptt_sent_at': time.time()} if ptt else {'notified': 1}))
                    if ptt:
                        in_flight.add(device['id'])
            except (httpx.HTTPError, OSError, ValueError, jwt.PyJWTError):
                attempts = event['attempts'] + 1
                self.store.update_event(event['id'], expected_delivery_id=device['id'], attempts=attempts,
                                        next_attempt_at=time.time() + min(300, 5 * 2 ** min(attempts, 6)))
                # Try alert delivery after PTT failure; keep the update recoverable regardless.
                if ptt and device['notification_token']:
                    try:
                        if await self.send(device, event, False):
                            self.store.update_event(event['id'], expected_delivery_id=device['id'], notified=1)
                    except (httpx.HTTPError, OSError, ValueError, jwt.PyJWTError):
                        pass
