import argparse
import os

from .store import Store
from .config import Settings


def main():
    parser = argparse.ArgumentParser(description='CAPA private Hermes companion')
    parser.add_argument('--database', default=os.environ.get('CAPA_DATABASE', str(Settings.database)))
    commands = parser.add_subparsers(dest='command', required=True)
    pair = commands.add_parser('pair', help='Issue a one-use code valid for five minutes')
    pair.add_argument('--link-device', help='Join the workspace of this existing active device ID')
    commands.add_parser('devices', help='List paired device IDs (never credentials)')
    revoke = commands.add_parser('revoke', help='Revoke a device and all push delivery')
    revoke.add_argument('device_id')
    serve = commands.add_parser('serve', help='Run a single bridge worker')
    serve.add_argument('--host', default='127.0.0.1')
    serve.add_argument('--port', type=int, default=8787)
    serve.add_argument('--tls-cert')
    serve.add_argument('--tls-key')
    args = parser.parse_args()
    os.umask(0o077)
    store = Store(args.database)
    if args.command == 'pair':
        try:
            print(store.issue_pairing_code(device_id=args.link_device))
        except ValueError as exc:
            parser.error(str(exc))
    elif args.command == 'devices':
        with store.connect() as db:
            for row in db.execute('SELECT id,name,revoked FROM devices'):
                print(f"{row['id']}  {row['name']}  {'revoked' if row['revoked'] else 'paired'}")
    elif args.command == 'revoke':
        if not store.revoke_device(args.device_id):
            parser.error('Unknown device')
        print('Device revoked. Existing Hermes work is not automatically cancelled.')
    else:
        if args.host not in ('127.0.0.1', 'localhost', '::1') and not (args.tls_cert and args.tls_key):
            parser.error('Use TLS for a network listener, or put a TLS reverse proxy in front of loopback')
        from .app import create_app
        import uvicorn
        settings = Settings.from_env()
        uvicorn.run(create_app(settings, store=store), host=args.host, port=args.port,
                    ssl_certfile=args.tls_cert, ssl_keyfile=args.tls_key, access_log=False)


if __name__ == '__main__':
    main()
