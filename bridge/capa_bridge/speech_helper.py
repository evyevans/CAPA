"""Subprocess entry point using the user's Hermes environment and speech settings.

No provider keys cross the bridge HTTP interface. Imports and provider execution
are opt-in through CAPA_HERMES_PYTHON and CAPA_HERMES_REPOSITORY.
"""
import contextlib
import json
import os
import sys


def main():
    request = json.load(sys.stdin)
    sys.path.insert(0, request['repository'])
    # Keep library chatter out of the JSON protocol; the bridge discards stderr.
    with contextlib.redirect_stdout(sys.stderr):
        from dotenv import load_dotenv
        from pathlib import Path
        load_dotenv(Path(os.environ.get('HERMES_HOME', '~/.hermes')).expanduser() / '.env', override=False)
        if request['operation'] == 'stt':
            from tools.transcription_tools import transcribe_audio
            result = transcribe_audio(request['path'], source='gateway')
        else:
            from tools.tts_tool import text_to_speech_tool
            result = json.loads(text_to_speech_tool(request['text'], output_path=request['path']))
    print(json.dumps(result))


if __name__ == '__main__':
    main()
