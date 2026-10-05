#!/usr/bin/env python3
"""Exercise the unmodified iOS Mach-O through Vinix's actual desktop protocol."""
import argparse
import os
from pathlib import Path
import select
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CASES = [('7+5=', '12'), ('3-9=', '-6'), ('12*8=', '96'), ('81/9=', '9'),
    ('0.1+0.2=', '0.3'), ('0002.50+0.25=', '2.75'), ('2+3*4=', '20'),
    ('5+*2=', '10'), ('5+=', '10'), ('2+3===', '11'), ('2+3=7', '7'),
    ('2+3=C', '0'), ('200+10%=', '220'), ('200-10%=', '180'),
    ('200*10%=', '20'), ('50%=', '0.5'), ('2s+5=', '3'), ('s2+5=', '3'),
    ('2ss', '2'), ('5+s2=', '3'), ('1/0=', 'Error'), ('1/0=+', 'Error'),
    ('1/0=7+2=', '9'), ('1/0=C', '0'), ('0..25', '0.25'),
    ('1234567890123456', '123456789012345'), ('9' + '*=' * 12, 'Error')]
TITLES = {'C': 'AC', 's': '±', '*': '×', '-': '−', '/': '÷'}


def read_exact(fd, size):
    data = bytearray()
    while len(data) < size:
        if not select.select([fd], [], [], 10)[0]:
            raise RuntimeError('UIKit desktop response timed out')
        chunk = os.read(fd, size - len(data))
        if not chunk:
            raise RuntimeError('UIKit desktop connection closed')
        data.extend(chunk)
    return bytes(data)


def decode_tree(data):
    def element(offset):
        if offset + 274 > len(data):
            raise ValueError('short element')
        kind, flags, align = data[offset:offset+3]
        frame = struct.unpack_from('<4d', data, offset+10)
        offset += 274
        strings = []
        for _ in range(12):
            length, = struct.unpack_from('<I', data, offset)
            offset += 4
            strings.append(data[offset:offset+length].decode())
            offset += length
        menus, = struct.unpack_from('<I', data, offset)
        assert menus == 0
        count, = struct.unpack_from('<I', data, offset+4)
        offset += 8
        children = []
        for _ in range(count):
            child, offset = element(offset)
            children.append(child)
        return dict(kind=kind, flags=flags, align=align, frame=frame,
                    id=strings[0], text=strings[3], children=children), offset
    tree, end = element(0)
    assert end == len(data), (end, len(data))
    return tree


class DesktopClient:
    def __init__(self, runner, binary):
        child_input, self.request = os.pipe()
        self.response, child_output = os.pipe()
        self.process = subprocess.Popen([str(runner), str(binary)],
            pass_fds=(child_input, child_output), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**os.environ, 'VINIX_REQUEST_FD': str(child_input),
                 'VINIX_RESPONSE_FD': str(child_output)})
        os.close(child_input)
        os.close(child_output)
        self.state = bytes(116)
        self.reply()
        assert struct.unpack_from("<I", self.state, 48)[0] in (1, 2)

    def reply(self):
        header = read_exact(self.response, 128)
        assert header[:8] == struct.pack('<IBBBB', 0x56415050, 10, 0, 0, 0)
        self.state = header[8:124]
        length, = struct.unpack_from('<I', header, 124)
        assert length <= 1024*1024
        return read_exact(self.response, length)

    def send(self, command, payload=b'', width=390, height=680):
        header = struct.pack('<IBBBBii', 0x56415050, 10, command, 0, 0, width, height)
        os.write(self.request, header + self.state + struct.pack('<I', len(payload)) + payload)
        return self.reply()

    def build(self, width=390, height=680):
        return decode_tree(self.send(1, width=width, height=height))

    def close(self):
        self.send(6)
        os.close(self.request)
        os.close(self.response)
        out, err = self.process.communicate(timeout=10)
        assert self.process.returncode == 0, (self.process.returncode, out, err)
        assert not err, err.decode(errors='replace')


def run(runner, binary):
    client = DesktopClient(runner, binary)
    tree = client.build()
    assert tree['kind'] == 0 and len(tree['children']) == 20
    buttons = {child['text']: child for child in tree['children'] if child['kind'] == 4}
    assert len(buttons) == 19 and tree['children'][0]['text'] == '0'
    for keys, expected in CASES:
        client.send(2, buttons['AC']['id'].encode())
        for key in keys:
            client.send(2, buttons[TITLES.get(key, key)]['id'].encode())
        actual = client.build()['children'][0]['text']
        assert actual == expected, (keys, expected, actual)
    for width, height in [(480, 800), (800, 480), (390, 680)]:
        tree = client.build(width, height)
        for child in tree['children']:
            x, y, w, h = child['frame']
            assert x >= 0 and y >= 0 and w > 0 and h > 0
            assert x+w <= width+0.001 and y+h <= height+0.001
    client.send(3, b'C7+5=')
    assert client.build()['children'][0]['text'] == '12'
    # Repeated layout and label replacement exercise autorelease/strong fields.
    for _ in range(1000):
        client.send(3, b'C2+3=')
        assert client.build()['children'][0]['text'] == '5'
    client.close()
    print('UIKit Mach-O: 27 button cases, resize, keyboard and 1000 update cycles passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, default=ROOT/'build/ios/run-ios-host')
    parser.add_argument('--binary', type=Path, default=ROOT/'build/ios/objc/Calculator.app/Calculator')
    args = parser.parse_args()
    run(args.runner, args.binary)
