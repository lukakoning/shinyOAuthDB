"""Expose a private database listener to host R without terminating its TLS."""
import asyncio
import os
import socket
import sys

target = int(os.environ['OAUTHDB_RELAY_TARGET_PORT'])


async def relay(reader, writer):
    upstream = None
    try:
        remote, upstream = await asyncio.open_connection('127.0.0.1', target)

        async def copy(source, destination):
            while data := await source.read(65536):
                destination.write(data)
                await destination.drain()
            if destination.can_write_eof():
                destination.write_eof()

        await asyncio.gather(copy(reader, upstream), copy(remote, writer))
    except (ConnectionError, OSError):
        pass
    finally:
        writer.close()
        if upstream is not None:
            upstream.close()


async def main():
    server = await asyncio.start_server(relay, '0.0.0.0', 19444)
    async with server:
        await server.serve_forever()


if '--check' in sys.argv:
    for port in (19444, target):
        with socket.create_connection(('127.0.0.1', port), timeout=2):
            pass
else:
    asyncio.run(main())
