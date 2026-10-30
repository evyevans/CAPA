from test_bridge import setup


def test_prepared_brief_is_reused_instead_of_regenerating_speech(tmp_path):
    import asyncio
    from capa_bridge.config import Settings
    from capa_bridge.speech import Speech
    settings = Settings(database=tmp_path / 'bridge.sqlite3', hermes_key='test')
    speech = Speech(settings)
    generated = []
    async def provider(text):
        generated.append(text)
        return b'encoded audio from provider'
    speech.synthesize = provider
    event = {'id': '8d9b6204-4e91-4b2b-9e7f-156a45b3e712', 'kind': 'completed', 'spoken_text': 'The work is ready.'}
    assert asyncio.run(speech.audio(event)) == b'encoded audio from provider'
    assert asyncio.run(speech.audio(event)) == b'encoded audio from provider'
    assert generated == ['The work is ready.']


def test_host_speech_is_opt_in_and_requires_device_auth(setup):
    http, _, _, _, headers, _ = setup
    assert http.post('/v1/transcribe', content=b'audio').status_code == 401
    response = http.post('/v1/transcribe', headers={**headers, 'Content-Type': 'audio/mp4'}, content=b'audio')
    assert response.status_code == 503


def test_speech_audio_is_scoped_to_event_owner(setup):
    http, _, _, _, headers, _ = setup
    assert http.post('/v1/events/missing/audio', headers=headers).status_code == 404


def test_explicit_null_availability_cannot_reenable_or_corrupt_device(setup):
    http, _, _, _, headers, _ = setup
    assert http.put('/v1/device', headers=headers, json={'available': None}).status_code == 422


def test_hermes_speech_helper_uses_existing_environment_and_preserves_audio_bytes(tmp_path):
    import asyncio
    import sys
    from capa_bridge.config import Settings
    from capa_bridge.speech import Speech
    # Only provider modules are stand-ins. The real subprocess protocol,
    # private temp files, path verification and cache are exercised.
    repository = tmp_path / 'hermes'
    tools = repository / 'tools'
    tools.mkdir(parents=True)
    (tools / '__init__.py').write_text('')
    (repository / 'dotenv.py').write_text('def load_dotenv(*args, **kwargs): pass\n')
    (tools / 'transcription_tools.py').write_text(
        'from pathlib import Path\n'
        'def transcribe_audio(path, source):\n'
        '    assert source == "gateway"\n'
        '    assert Path(path).read_bytes() == b"recorded memo"\n'
        '    return {"success": True, "transcript": "Research batteries"}\n')
    (tools / 'tts_tool.py').write_text(
        'import json\nfrom pathlib import Path\n'
        'def text_to_speech_tool(text, output_path):\n'
        '    print("provider chatter")\n'
        '    Path(output_path).write_bytes(b"encoded brief")\n'
        '    return json.dumps({"success": True, "file_path": output_path})\n')
    speech = Speech(Settings(database=tmp_path / 'bridge.sqlite3', hermes_key='test',
                             hermes_python=sys.executable, hermes_repository=str(repository)))
    assert asyncio.run(speech.transcribe(b'recorded memo')) == 'Research batteries'
    assert asyncio.run(speech.audio({'id': '941c1bdc-5bc1-444c-b046-fc7f75a8aaf7', 'kind': 'completed',
                                    'spoken_text': 'Your research is ready.'})) == b'encoded brief'
