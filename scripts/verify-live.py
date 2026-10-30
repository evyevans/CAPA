#!/usr/bin/env python3
"""Opt-in, harmless real-provider smoke test; never prints device credentials."""
import argparse
import getpass
import json
import os
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', default='http://127.0.0.1:8787')
    parser.add_argument('--submit', action='store_true', help='Allow a real Hermes request using your configured provider')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    url = urlparse(args.bridge)
    if url.username or url.password or url.query or url.fragment or not url.hostname or not (
        url.scheme == 'https' or (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost', '::1'))
    ):
        parser.error('Use HTTPS, or HTTP on loopback only; no embedded credentials.')
    if not args.submit:
        parser.error('--submit explicitly permits one real model request; provider usage applies.')
    code = os.environ.get('CAPA_SMOKE_PAIR_CODE') or getpass.getpass('One-use host pairing code: ')
    tokens = []
    report = {'checks': [], 'passed': False}

    def call(path, token=None, body=None, method=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        request = Request(args.bridge.rstrip('/') + '/' + path, headers=headers,
                          data=json.dumps(body).encode() if body is not None else None,
                          method=method or ('POST' if body is not None else 'GET'))
        # Refuse redirects rather than sending pairing bodies to another endpoint.
        from urllib.request import HTTPRedirectHandler, build_opener
        class NoRedirect(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        with build_opener(NoRedirect).open(request, timeout=30) as response:
            return json.load(response)

    def check(condition, label):
        if not condition:
            raise RuntimeError(label)
        report['checks'].append(label)
        print('PASS:', label, flush=True)

    try:
        first = call('v1/pair', body={'code': code, 'name': 'CAPA live smoke A', 'platform': 'macos'})
        tokens.append(first['token'])
        invite = call('v1/devices/link', tokens[0], {})
        second = call('v1/pair', body={'code': invite['code'], 'name': 'CAPA live smoke B', 'platform': 'macos'})
        tokens.append(second['token'])
        one, two = [call('v1/me', token) for token in tokens]
        check(one['workspace_id'] == two['workspace_id'], 'Linked clients share a real workspace')
        check(one['reply_mode'] == 'notifications', 'Notifications are the workspace default')
        inventory = call('v1/connections', tokens[0])
        report['discovered_toolsets'] = len(inventory.get('toolsets', []))
        check(inventory['discovery_available'], 'Real Hermes tool discovery responds')
        memo = {'request_id': uuid.uuid4().hex,
                'text': 'CAPA connection verification. Reply exactly: CAPA live connection verified. Do not use tools or perform any external actions.'}
        task = call('v1/tasks', tokens[0], memo)
        repeated = call('v1/tasks', tokens[1], memo)
        check(task['id'] == repeated['id'], 'Retry from a second client retains one task')
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            task = call('v1/tasks/' + task['id'], tokens[1])
            if task['status'] in ('completed', 'failed', 'cancelled', 'interrupted', 'unknown', 'incomplete'):
                break
            time.sleep(2)
        report.update(task_id=task['id'], status=task['status'], run_id=task.get('run_id'))
        check(bool(task.get('run_id')), 'Hermes confirms an actual run identity')
        check(task['status'] == 'completed', 'Real Hermes run completes')
        check('CAPA live connection verified' in task.get('output', ''), 'Expected result is recovered on the second client')
        events = call('v1/events', tokens[1])
        check(any(event['task_id'] == task['id'] for event in events), 'Completion remains available as a delivery event')
        check(call('v1/tasks/' + task['id'], tokens[0])['output'] == task['output'], 'Both clients recover the same completed result')
        report['passed'] = True
    except HTTPError as error:
        report['error'] = f'HTTP {error.code}; no credentials or raw response logged'
    except Exception as error:
        report['error'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
    finally:
        for token in tokens:
            try:
                call('v1/device', token, method='DELETE')
            except Exception:
                report.setdefault('cleanup_errors', 0)
                report['cleanup_errors'] += 1
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('Live verification:', 'PASS' if report['passed'] else 'FAIL', flush=True)
    if report.get('error'):
        print(report['error'])
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
