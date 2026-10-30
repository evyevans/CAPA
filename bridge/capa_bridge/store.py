from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
import uuid


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class Store:
    def __init__(self, path: Path):
        self.path = Path(path).expanduser()
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Reserve with private permissions before SQLite creates sidecar files.
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        os.chmod(self.path, 0o600)
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS pairing_codes (
                    hash TEXT PRIMARY KEY, expires_at REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
                    session_id TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
                    available INTEGER NOT NULL DEFAULT 0, ptt_token TEXT,
                    notification_token TEXT, channel_id TEXT);
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY, device_id TEXT NOT NULL, request_id TEXT NOT NULL,
                    text TEXT NOT NULL, payload TEXT NOT NULL, run_id TEXT,
                    status TEXT NOT NULL, output TEXT NOT NULL DEFAULT '',
                    controls TEXT NOT NULL DEFAULT '[]', created_at REAL NOT NULL,
                    UNIQUE(device_id, request_id));
                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY, device_id TEXT NOT NULL, task_id TEXT NOT NULL,
                    fingerprint TEXT UNIQUE NOT NULL, kind TEXT NOT NULL,
                    text TEXT NOT NULL, spoken_text TEXT NOT NULL, created_at REAL NOT NULL,
                    acknowledged INTEGER NOT NULL DEFAULT 0, notified INTEGER NOT NULL DEFAULT 0,
                    ptt_sent_at REAL, attempts INTEGER NOT NULL DEFAULT 0,
                    next_attempt_at REAL NOT NULL DEFAULT 0);
            ''')

        self._migrate_workspaces()

    def _migrate_workspaces(self):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute("CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, "
                       "session_id TEXT NOT NULL, preferred_device_id TEXT, reply_mode TEXT NOT NULL DEFAULT 'notifications')")
            additions = {
                'devices': {'workspace_id': 'TEXT', 'platform': "TEXT NOT NULL DEFAULT 'ios'"},
                'pairing_codes': {'workspace_id': 'TEXT', 'issuer_id': 'TEXT'},
                'events': {'delivery_device_id': 'TEXT', 'lease_device_id': 'TEXT',
                           'lease_token_hash': 'TEXT', 'lease_expires_at': 'REAL NOT NULL DEFAULT 0'},
            }
            for table, columns in additions.items():
                present = {r['name'] for r in db.execute(f'PRAGMA table_info({table})')}
                for name, definition in columns.items():
                    if name not in present:
                        db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')
            for device in db.execute('SELECT * FROM devices WHERE workspace_id IS NULL').fetchall():
                workspace_id = str(uuid.uuid4())
                db.execute('INSERT INTO workspaces (id,name,session_id,preferred_device_id) VALUES (?,?,?,?)',
                           (workspace_id, 'My Hermes', device['session_id'], device['id']))
                db.execute('UPDATE devices SET workspace_id=? WHERE id=?', (workspace_id, device['id']))
            db.execute('UPDATE events SET delivery_device_id=device_id WHERE delivery_device_id IS NULL')
            db.execute('PRAGMA user_version=2')

    def workspace_for(self, device_id):
        with self.connect() as db:
            row = db.execute('SELECT w.* FROM workspaces w JOIN devices d ON d.workspace_id=w.id WHERE d.id=?',
                             (device_id,)).fetchone()
        return dict(row) if row else None

    def devices(self, device_id):
        workspace = self.workspace_for(device_id)
        with self.connect() as db:
            rows = db.execute('SELECT id,name,platform,available,revoked FROM devices WHERE workspace_id=? ORDER BY rowid',
                              (workspace['id'],)).fetchall()
        return [dict(row) for row in rows]

    def _destination(self, db, origin_id):
        workspace = db.execute('SELECT w.* FROM workspaces w JOIN devices d ON d.workspace_id=w.id WHERE d.id=?',
                               (origin_id,)).fetchone()
        row = db.execute('SELECT id FROM devices WHERE workspace_id=? AND revoked=0 ORDER BY '
                         '(id=?) DESC, (id=?) DESC, rowid LIMIT 1',
                         (workspace['id'], workspace['preferred_device_id'], origin_id)).fetchone()
        return row['id'] if row else origin_id

    def update_workspace(self, device_id, fields):
        workspace = self.workspace_for(device_id)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            preferred = fields.get('preferred_device_id', workspace['preferred_device_id'])
            if preferred:
                found = db.execute('SELECT id FROM devices WHERE id=? AND workspace_id=? AND revoked=0',
                                   (preferred, workspace['id'])).fetchone()
                if not found:
                    raise ValueError('Choose an active device in this workspace')
            values = {k: v for k, v in fields.items() if k in ('name', 'reply_mode', 'preferred_device_id')}
            if values:
                db.execute('UPDATE workspaces SET ' + ','.join(f'{k}=?' for k in values) + ' WHERE id=?',
                           [*values.values(), workspace['id']])
            if 'preferred_device_id' in fields:
                db.execute('UPDATE events SET delivery_device_id=?,ptt_sent_at=NULL,notified=0,next_attempt_at=0 '
                           'WHERE acknowledged=0 AND delivery_device_id<>? '
                           'AND device_id IN (SELECT id FROM devices WHERE workspace_id=?)',
                           (preferred, preferred, workspace['id']))
        return self.workspace_for(device_id)

    def claim(self, event_id, device_id, token, manual):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            event = db.execute('SELECT e.* FROM events e JOIN devices owner ON owner.id=e.device_id '
                               'JOIN devices viewer ON viewer.workspace_id=owner.workspace_id '
                               'WHERE e.id=? AND viewer.id=? AND viewer.revoked=0', (event_id, device_id)).fetchone()
            if not event or event['acknowledged']:
                raise ValueError('Update is no longer pending')
            if event['lease_expires_at'] > time.time() and (
                    event['lease_device_id'] != device_id or event['lease_token_hash'] != digest(token)):
                raise ValueError('This update is playing on another device')
            if not manual:
                row = db.execute('SELECT d.available,w.reply_mode,w.preferred_device_id FROM devices d JOIN workspaces w '
                                 'ON w.id=d.workspace_id WHERE d.id=?', (device_id,)).fetchone()
                if (event['delivery_device_id'] != device_id or row['preferred_device_id'] != device_id or
                        not row['available'] or row['reply_mode'] != 'spoken'):
                    raise ValueError('Automatic speech is not enabled on this device')
            db.execute('UPDATE events SET lease_device_id=?,lease_token_hash=?,lease_expires_at=? WHERE id=?',
                       (device_id, digest(token), time.time() + 120, event_id))

    def acknowledge(self, event_id, device_id, token=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            event = db.execute('SELECT * FROM events WHERE id=?', (event_id,)).fetchone()
            # Old single-device clients retain an unclaimed-origin receipt path.
            # Once claimed, every client must provide the exact playback token.
            if event['lease_token_hash']:
                if event['lease_device_id'] != device_id or not token or event['lease_token_hash'] != digest(token):
                    raise ValueError('Playback receipt does not match the current claim')
            elif device_id != event['device_id']:
                raise ValueError('Claim this update before acknowledging playback')
            db.execute('UPDATE events SET acknowledged=1 WHERE id=?', (event_id,))

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def issue_pairing_code(self, ttl=300, device_id=None):
        code = secrets.token_urlsafe(12)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            workspace_id = None
            if device_id:
                row = db.execute('SELECT workspace_id FROM devices WHERE id=? AND revoked=0', (device_id,)).fetchone()
                if not row:
                    raise ValueError('Issuer is not active')
                workspace_id = row['workspace_id']
            db.execute('DELETE FROM pairing_codes WHERE expires_at < ?', (time.time(),))
            db.execute('INSERT INTO pairing_codes (hash,expires_at,workspace_id,issuer_id) VALUES (?,?,?,?)',
                       (digest(code), time.time() + ttl, workspace_id, device_id))
        return code

    def pair(self, code, name, platform='ios'):
        token, device_id = secrets.token_urlsafe(32), str(uuid.uuid4())
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            invite = db.execute('SELECT * FROM pairing_codes WHERE hash=? AND expires_at>=?',
                                (digest(code), time.time())).fetchone()
            if not invite:
                return None
            if invite['issuer_id'] and not db.execute('SELECT id FROM devices WHERE id=? AND revoked=0',
                                                       (invite['issuer_id'],)).fetchone():
                return None
            workspace_id = invite['workspace_id'] or str(uuid.uuid4())
            workspace = db.execute('SELECT * FROM workspaces WHERE id=?', (workspace_id,)).fetchone()
            session_id = workspace['session_id'] if workspace else f'capa-{workspace_id}'
            if not workspace:
                db.execute('INSERT INTO workspaces (id,name,session_id,preferred_device_id) VALUES (?,?,?,?)',
                           (workspace_id, 'My Hermes', session_id, device_id))
            db.execute('DELETE FROM pairing_codes WHERE hash=?', (digest(code),))
            db.execute('INSERT INTO devices (id,name,token_hash,session_id,workspace_id,platform) VALUES (?,?,?,?,?,?)',
                       (device_id, name, digest(token), session_id, workspace_id, platform))
        return {'device_id': device_id, 'token': token, 'workspace_id': workspace_id}

    def authenticate(self, token):
        with self.connect() as db:
            row = db.execute('SELECT * FROM devices WHERE token_hash=? AND revoked=0', (digest(token),)).fetchone()
        return dict(row) if row else None

    def device(self, device_id):
        with self.connect() as db:
            row = db.execute('SELECT * FROM devices WHERE id=?', (device_id,)).fetchone()
        return dict(row) if row else None

    def revoke_device(self, device_id):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            changed = db.execute('UPDATE devices SET revoked=1,available=0,ptt_token=NULL,notification_token=NULL '
                                 'WHERE id=?', (device_id,)).rowcount == 1
            db.execute('DELETE FROM pairing_codes WHERE issuer_id=?', (device_id,))
            device = db.execute('SELECT workspace_id FROM devices WHERE id=?', (device_id,)).fetchone()
            if device:
                replacement = db.execute('SELECT id FROM devices WHERE workspace_id=? AND revoked=0 ORDER BY rowid LIMIT 1',
                                         (device['workspace_id'],)).fetchone()
                if replacement:
                    db.execute('UPDATE workspaces SET preferred_device_id=? WHERE id=? AND preferred_device_id=?',
                               (replacement['id'], device['workspace_id'], device_id))
                    db.execute('UPDATE events SET delivery_device_id=?,ptt_sent_at=NULL,notified=0,next_attempt_at=0 '
                               'WHERE delivery_device_id=? AND acknowledged=0',
                               (replacement['id'], device_id))
            return changed

    def update_device(self, device_id, fields):
        # Keys come from the validated HTTP model, never from request SQL text.
        allowed = {'available', 'ptt_token', 'notification_token', 'channel_id', 'name'}
        values = {k: v for k, v in fields.items() if k in allowed}
        if values.get('available') is False:
            values['ptt_token'] = None
            values['channel_id'] = None
        if values:
            with self.connect() as db:
                db.execute('UPDATE devices SET ' + ','.join(f'{k}=?' for k in values) + ' WHERE id=?',
                           [*values.values(), device_id])

    def reserve_task(self, device, request_id, text):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            old = db.execute('SELECT t.* FROM tasks t JOIN devices d ON d.id=t.device_id '
                             'WHERE d.workspace_id=? AND t.request_id=?',
                             (device['workspace_id'], request_id)).fetchone()
            if old:
                if old['text'] != text:
                    raise ValueError('Request ID already used for different work')
                return self.decode_task(old)
            task_id = str(uuid.uuid4())
            payload = {'input': text, 'session_id': device['session_id'], 'instructions':
                       'You are communicating through CAPA. Do the requested work using '
                       'your existing tools and policies. Ask genuine clarifications through the '
                       'configured clarification mechanism. Keep the final spoken brief concise '
                       'with an opening paragraph of two plain spoken sentences, followed by '
                       'sources and details in later paragraphs. Do not claim work succeeded '
                       'unless verified. Do not detach work that will outlive this run; await its '
                       'result so this client can deliver completion reliably.'}
            db.execute('INSERT INTO tasks (id,device_id,request_id,text,payload,status,created_at) '
                       'VALUES (?,?,?,?,?,?,?)', (task_id, device['id'], request_id, text,
                                                 json.dumps(payload), 'submitting', time.time()))
            return self.decode_task(db.execute('SELECT * FROM tasks WHERE id=?', (task_id,)).fetchone())

    @staticmethod
    def decode_task(row):
        result = dict(row)
        result['controls'] = json.loads(result['controls'])
        result['payload'] = json.loads(result['payload'])
        return result

    def task(self, task_id, device_id=None):
        with self.connect() as db:
            if device_id:
                row = db.execute('SELECT t.* FROM tasks t JOIN devices owner ON owner.id=t.device_id '
                                 'JOIN devices viewer ON viewer.workspace_id=owner.workspace_id '
                                 'WHERE t.id=? AND viewer.id=? AND viewer.revoked=0', (task_id, device_id)).fetchone()
            else:
                row = db.execute('SELECT * FROM tasks WHERE id=?', (task_id,)).fetchone()
        return self.decode_task(row) if row else None

    def tasks(self, device_id=None, active=False):
        where, args = [], []
        if device_id:
            where.append('device_id IN (SELECT id FROM devices WHERE workspace_id='
                         '(SELECT workspace_id FROM devices WHERE id=? AND revoked=0))')
            args.append(device_id)
        if active:
            where.append("status NOT IN ('completed','failed','cancelled','interrupted','unknown')")
        with self.connect() as db:
            rows = db.execute('SELECT * FROM tasks' + (' WHERE ' + ' AND '.join(where) if where else '') +
                              ' ORDER BY created_at DESC', args).fetchall()
        return [self.decode_task(row) for row in rows]

    def update_task(self, task_id, **fields):
        values = {k: json.dumps(v) if k == 'controls' else v for k, v in fields.items()
                  if k in ('status', 'run_id', 'output', 'controls')}
        with self.connect() as db:
            db.execute('UPDATE tasks SET ' + ','.join(f'{k}=?' for k in values) + ' WHERE id=?',
                       [*values.values(), task_id])

    def add_event(self, task, kind, text, identity=''):
        with self.connect() as db:
            self._insert_event(db, task, kind, text, identity)

    def _insert_event(self, db, task, kind, text, identity=''):
        spoken = text.split('\n\n')[0].strip()[:800] or 'Hermes has an update for you.'
        db.execute('INSERT OR IGNORE INTO events '
                   '(id,device_id,task_id,fingerprint,kind,text,spoken_text,created_at,delivery_device_id) VALUES (?,?,?,?,?,?,?,?,?)',
                   (str(uuid.uuid4()), task['device_id'], task['id'], f"{task['id']}:{kind}:{identity}",
                    kind, text, spoken, time.time(), self._destination(db, task['device_id'])))

    def snapshot(self, task, status, output='', controls=None, notices=()):
        """Never persist terminal state without its recoverable delivery event."""
        controls = controls or []
        current = {f"{task['id']}:{kind}:{identity}" for kind, _, identity in notices
                   if kind in ('clarification', 'approval')}
        with self.connect() as db:
            db.execute('UPDATE tasks SET status=?,output=?,controls=? WHERE id=?',
                       (status, output, json.dumps(controls), task['id']))
            rows = db.execute("SELECT id,fingerprint FROM events WHERE task_id=? "
                              "AND kind IN ('clarification','approval') AND acknowledged=0", (task['id'],)).fetchall()
            for row in rows:
                if row['fingerprint'] not in current:
                    db.execute('UPDATE events SET acknowledged=1 WHERE id=?', (row['id'],))
            for kind, text, identity in notices:
                self._insert_event(db, task, kind, text, identity)

    def events(self, device_id=None, pending=True):
        clauses, args = (['device_id IN (SELECT id FROM devices WHERE workspace_id='
                         '(SELECT workspace_id FROM devices WHERE id=? AND revoked=0))'], [device_id]) if device_id else ([], [])
        if pending:
            clauses.append('acknowledged=0')
        with self.connect() as db:
            rows = db.execute('SELECT * FROM events' + (' WHERE ' + ' AND '.join(clauses) if clauses else '') +
                              ' ORDER BY created_at,id', args).fetchall()
        return [dict(r) for r in rows]

    def event(self, event_id, device_id):
        with self.connect() as db:
            row = db.execute('SELECT e.* FROM events e JOIN devices owner ON owner.id=e.device_id '
                             'JOIN devices viewer ON viewer.workspace_id=owner.workspace_id '
                             'WHERE e.id=? AND viewer.id=? AND viewer.revoked=0', (event_id, device_id)).fetchone()
        return dict(row) if row else None

    def update_event(self, event_id, expected_delivery_id=None, **fields):
        allowed = {'acknowledged', 'notified', 'ptt_sent_at', 'attempts', 'next_attempt_at'}
        values = {k: v for k, v in fields.items() if k in allowed}
        if not values:
            return 0
        condition = ' AND delivery_device_id=?' if expected_delivery_id is not None else ''
        parameters = [*values.values(), event_id]
        if expected_delivery_id is not None:
            parameters.append(expected_delivery_id)
        with self.connect() as db:
            return db.execute('UPDATE events SET ' + ','.join(f'{k}=?' for k in values) + ' WHERE id=?' + condition,
                              parameters).rowcount

    def retire_controls(self, task_id, current_fingerprints):
        with self.connect() as db:
            rows = db.execute("SELECT id,fingerprint FROM events WHERE task_id=? "
                              "AND kind IN ('clarification','approval') AND acknowledged=0", (task_id,)).fetchall()
            for row in rows:
                if row['fingerprint'] not in current_fingerprints:
                    db.execute('UPDATE events SET acknowledged=1 WHERE id=?', (row['id'],))
