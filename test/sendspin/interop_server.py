"""Drives Puffer's Sendspin player from aiosendspin, the library Music Assistant uses.

Usage: python interop_server.py <ws-url> <client-id>
Connects to the player, approves it for unpaired playback, sends three seconds of a 440 Hz tone and prints DONE.
"""

import asyncio
import math
import struct
import sys

from aiosendspin.audio.format import AudioFormat
from aiosendspin.models.types import ConnectionReason
from aiosendspin.noise.keys import Identity
from aiosendspin.noise.trust_store import InMemoryServerPairingStore
from aiosendspin.server.server import SendspinServer


def tone(start_frame: int, frames: int, rate: int) -> bytes:
    samples = []
    for i in range(frames):
        value = int(8000 * math.sin(2 * math.pi * 440 * (start_frame + i) / rate))
        samples += [value, value]
    return struct.pack(f"<{len(samples)}h", *samples)


async def main(url: str, client_id: str) -> None:
    loop = asyncio.get_running_loop()
    server = SendspinServer(loop, Identity.generate(), "Interop test", pairing_store=InMemoryServerPairingStore())
    await server.trust_unpaired(client_id)
    server.connect_to_client(url, connection_reason=ConnectionReason.PLAYBACK)

    client = None
    for _ in range(300):
        client = server.get_client(client_id)
        if client is not None and client.is_connected and client.available:
            break
        await asyncio.sleep(0.05)
    else:
        print("NOT READY", flush=True)
        await server.close()
        sys.exit(1)
    print("READY", flush=True)

    rate, frames = 48000, 960  # 20 ms chunks
    fmt = AudioFormat(sample_rate=rate, bit_depth=16, channels=2)
    stream = client.group.start_stream()
    for n in range(150):
        stream.prepare_audio(tone(n * frames, frames, rate), fmt)
        await stream.commit_audio()
        await stream.sleep_to_limit_buffer(500_000)
    await asyncio.sleep(1)
    print("DONE", flush=True)
    await server.close()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], sys.argv[2]))
