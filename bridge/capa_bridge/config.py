from dataclasses import dataclass
from pathlib import Path
import os
from urllib.parse import urlparse


@dataclass(frozen=True)
class Settings:
    database: Path = Path.home() / '.local/share/capa/bridge.sqlite3'
    hermes_url: str = 'http://127.0.0.1:8642'
    hermes_key: str = ''
    poll_seconds: float = 3
    apns_team_id: str = ''
    apns_key_id: str = ''
    apns_key_path: str = ''
    apns_bundle_id: str = ''
    apns_sandbox: bool = True
    hermes_python: str = ''
    hermes_repository: str = ''

    def __post_init__(self):
        url = urlparse(self.hermes_url)
        if url.scheme not in ('https', 'http') or not url.hostname or url.username or url.password:
            raise ValueError('Hermes URL must be HTTP(S), without embedded credentials')
        if url.scheme == 'http' and url.hostname not in ('127.0.0.1', 'localhost', '::1'):
            raise ValueError('Remote Hermes connections require HTTPS')
        if not self.hermes_key:
            raise ValueError('CAPA_HERMES_KEY is required')
        if self.poll_seconds < 1:
            raise ValueError('Poll interval must be at least one second')

    @classmethod
    def from_env(cls):
        return cls(
            database=Path(os.environ.get('CAPA_DATABASE', str(cls.database))).expanduser(),
            hermes_url=os.environ.get('CAPA_HERMES_URL', cls.hermes_url),
            hermes_key=os.environ.get('CAPA_HERMES_KEY', ''),
            poll_seconds=float(os.environ.get('CAPA_POLL_SECONDS', '3')),
            apns_team_id=os.environ.get('CAPA_APNS_TEAM_ID', ''),
            apns_key_id=os.environ.get('CAPA_APNS_KEY_ID', ''),
            apns_key_path=os.environ.get('CAPA_APNS_KEY_PATH', ''),
            apns_bundle_id=os.environ.get('CAPA_APNS_BUNDLE_ID', ''),
            apns_sandbox=os.environ.get('CAPA_APNS_SANDBOX', 'true').lower() == 'true',
            hermes_python=os.environ.get('CAPA_HERMES_PYTHON', ''),
            hermes_repository=os.environ.get('CAPA_HERMES_REPOSITORY', ''),
        )
