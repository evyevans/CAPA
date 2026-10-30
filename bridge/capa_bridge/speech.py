import asyncio
import json
from pathlib import Path
import tempfile
import os
import uuid


class SpeechUnavailable(Exception):
    pass


class Speech:
    """Execute only the operator-selected Hermes Python, never client-supplied commands."""
    def __init__(self, settings):
        self.settings = settings
        self.configured = bool(settings.hermes_python and settings.hermes_repository)
        self.lock = asyncio.Lock()
        self.cache_lock = asyncio.Lock()

    async def audio(self, event):
        identifier = str(uuid.UUID(event['id']))
        root = self.settings.database.expanduser().parent / 'capa-audio'
        path = root / f'{identifier}.mp3'
        async with self.cache_lock:
            if path.is_file():
                return path.read_bytes()
            text = ('Hermes needs your approval. Open CAPA to review the action.'
                    if event['kind'] == 'approval' else event['spoken_text'])
            data = await self.synthesize(text)
            root.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = root / f'{identifier}.tmp'
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'wb') as file:
                file.write(data)
            temporary.replace(path)
            return data

    async def run(self, operation, directory, **fields):
        if not self.configured:
            raise SpeechUnavailable('Host speech is not configured; use device speech')
        helper = Path(__file__).with_name('speech_helper.py')
        proc = await asyncio.create_subprocess_exec(
            self.settings.hermes_python, str(helper),
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            cwd=self.settings.hermes_repository)
        try:
            output, _ = await asyncio.wait_for(proc.communicate(json.dumps({
                'operation': operation, 'repository': self.settings.hermes_repository,
                'directory': str(directory), **fields}).encode()), timeout=90)
        except (TimeoutError, asyncio.CancelledError):
            if proc.returncode is None:
                proc.kill()
            await proc.wait()
            raise
        if proc.returncode:
            raise SpeechUnavailable('The configured Hermes speech provider could not complete the request')
        try:
            result = json.loads(output)
        except ValueError:
            raise SpeechUnavailable('Hermes speech returned an unsupported response')
        if not result.get('success'):
            raise SpeechUnavailable('Hermes speech did not succeed; use device speech or retry')
        return result

    async def transcribe(self, audio):
        async with self.lock:
            with tempfile.TemporaryDirectory(prefix='capa-stt-') as root:
                path = Path(root) / 'memo.m4a'
                path.write_bytes(audio)
                result = await self.run('stt', root, path=str(path))
                text = result.get('transcript', '')
                if not isinstance(text, str) or not text.strip() or len(text) > 20000:
                    raise SpeechUnavailable('No usable transcript returned')
                return text.strip()

    async def synthesize(self, text):
        async with self.lock:
            with tempfile.TemporaryDirectory(prefix='capa-tts-') as root:
                path = Path(root) / 'brief.mp3'
                result = await self.run('tts', root, text=text, path=str(path))
                generated = Path(result.get('file_path', '')).resolve()
                if not generated.is_relative_to(Path(root).resolve()) or not generated.is_file():
                    raise SpeechUnavailable('Hermes did not produce audio in the requested temporary directory')
                if generated.stat().st_size > 10 * 1024 * 1024:
                    raise SpeechUnavailable('Spoken brief exceeded the delivery limit')
                return generated.read_bytes()
