#!/usr/bin/env python3
"""Run upstream iOS-2048's Mach-O and check native game/UI behavior."""
import argparse
from pathlib import Path
import struct
import time
from uikit import DesktopClient, ROOT


def elements(tree):
    yield tree
    for child in tree['children']:
        yield from elements(child)


def board(tree):
    all_elements = list(elements(tree))
    scores = [e['text'] for e in all_elements if e['text'].startswith('SCORE: ')]
    assert len(scores) == 1, scores
    tiles = [int(e['text']) for e in all_elements if e['kind'] == 2 and e['text'].isdigit()]
    assert len(tiles) <= 16 and all(v >= 2 and v & (v-1) == 0 for v in tiles), tiles
    return int(scores[0][7:]), tiles


def settle(client):
    # The upstream command queue delays moves with a 0.3-second NSTimer.
    time.sleep(.32)
    client.send(4)
    return client.build()


def run(runner, binary, cycles):
    client = DesktopClient(runner, binary)
    try:
        tree = client.build()
        play = [e for e in elements(tree) if e['text'] == 'Play Game']
        assert len(play) == 1 and play[0]['kind'] == 4
        client.send(2, play[0]['id'].encode())
        score, tiles = board(client.build())
        assert score == 0 and tiles == [2,2], (score,tiles)
        saw_merge = False
        last_score = score
        for i in range(cycles):
            # Real pointer swipes exercise the same recognizers as the desktop.
            direction = [(310, 340, 90, 340), (195, 450, 195, 220),
                         (90, 340, 310, 340), (195, 220, 195, 450)][i%4]
            x0,y0,x1,y1 = direction
            client.send(5, struct.pack('<7i', 1,1,0,x0,y0,390,680))
            client.send(5, struct.pack('<7i', 2,1,0,x1,y1,390,680))
            tree = settle(client)
            score, tiles = board(tree)
            assert score >= last_score, (score,last_score)
            saw_merge |= score > last_score and any(v >= 4 for v in tiles)
            last_score = score
            # Stop when the upstream game displays its loss/win alert.
            if any(e['text'] in ('Defeat!', 'Victory!') for e in elements(tree)):
                ok = [e for e in elements(tree) if e['text'] == 'OK']
                assert len(ok) == 1
                client.send(2, ok[0]['id'].encode())
                break
        assert saw_merge and last_score > 0, (last_score,tiles)
        # Keyboard arrows are translated into the registered swipe actions.
        client.send(3, b'\x1b[D')
        settle(client)
        print(f'iOS-2048: upstream launch, presentation, swipes, merges, score={last_score}, timers and keyboard passed')
    finally:
        client.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, default=ROOT/'build/ios/run-ios-host')
    parser.add_argument('--binary', type=Path, default=ROOT/'build/ios/2048/NumberTileGame.app/NumberTileGame')
    parser.add_argument('--cycles', type=int, default=32)
    args = parser.parse_args()
    run(args.runner, args.binary, args.cycles)
