"""Pairs Puffer's Sendspin player with aiosendspin, the library Music Assistant uses, through the pairing token.

Usage: python interop_pairing.py <ws-url> <pairing-token>
Connects unpaired, pairs with the token as an operator pasting it would, streams a second of a tone on the paired session, then connects again with a fresh server that shares the identity and pairing store, and prints PAIRED, STREAMED and RECONNECTED as each step succeeds.
"""

import asyncio
import math
import struct
import sys

from aiosendspin.audio.format import AudioFormat
from aiosendspin.models.types import ConnectionReason, PairMethod
from aiosendspin.noise.keys import Identity
from aiosendspin.noise.pairing import PairingAttempt
from aiosendspin.noise.pairing_token import decode_psk_token
from aiosendspin.noise.trust_store import InMemoryServerPairingStore
from aiosendspin.server.server import SendspinServer


def tone(start_frame: int, frames: int, rate: int) -> bytes:
    samples = []
    for i in range(frames):
        value = int(8000 * math.sin(2 * math.pi * 440 * (start_frame + i) / rate))
        samples += [value, value]
    return struct.pack(f"<{len(samples)}h", *samples)


async def wait_for(condition, what: str) -> None:
    for _ in range(300):
        if condition():
            return
        await asyncio.sleep(0.05)
    print(f"TIMEOUT {what}", flush=True)
    sys.exit(1)


async def main(url: str, token: str) -> None:
    loop = asyncio.get_running_loop()
    identity = Identity.generate()
    store = InMemoryServerPairingStore()
    decoded = decode_psk_token(token)
    client_id = decoded.client_id

    server = SendspinServer(loop, identity, "Interop pairing", pairing_store=store)
    server.connect_to_client(url, connection_reason=ConnectionReason.DISCOVERY)
    await wait_for(lambda: (c := server.get_client(client_id)) is not None and c.is_connected, "connect")

    attempt = PairingAttempt(
        method=PairMethod.PAIRING_PSK,
        pairing_psk=decoded.pairing_psk,
        client_id=client_id,
    )
    await asyncio.wait_for(server.initiate_pairing(client_id, attempt), 20)
    await wait_for(lambda: server.get_client(client_id).is_paired, "paired session")
    print("PAIRED", flush=True)

    client = server.get_client(client_id)
    # The player reports itself unavailable until its clock converges; the server counts it available before that first report.
    await asyncio.sleep(0.5)
    await wait_for(lambda: client.available, "available")
    rate, frames = 48000, 960
    fmt = AudioFormat(sample_rate=rate, bit_depth=16, channels=2)
    stream = client.group.start_stream()
    for n in range(50):
        stream.prepare_audio(tone(n * frames, frames, rate), fmt)
        await stream.commit_audio()
        await stream.sleep_to_limit_buffer(500_000)
    await asyncio.sleep(0.5)
    print("STREAMED", flush=True)
    await server.close()

    again = SendspinServer(loop, identity, "Interop pairing", pairing_store=store)
    again.connect_to_client(url, connection_reason=ConnectionReason.PLAYBACK)
    await wait_for(
        lambda: (c := again.get_client(client_id)) is not None and c.is_connected and c.is_paired,
        "paired reconnect",
    )
    print("RECONNECTED", flush=True)
    await again.close()
    print("DONE", flush=True)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], sys.argv[2]))
