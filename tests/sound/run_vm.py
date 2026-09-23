#!/usr/bin/env python3
"""Boot Vinix with a recording sound card and check what the guest played."""

from __future__ import annotations

import argparse
import errno
import importlib.util
import os
from pathlib import Path
import platform
import pty
import select
import sys
import time

# Share the core regression's QEMU process helpers. Its module is also called
# run_vm, so load it under another name.
_core_path = Path(__file__).resolve().parents[1] / "qemu-core" / "run_vm.py"
_core_spec = importlib.util.spec_from_file_location("qemu_core_run_vm", _core_path)
_core = importlib.util.module_from_spec(_core_spec)
_core_spec.loader.exec_module(_core)
available_port = _core.available_port
exit_code = _core.exit_code
stop_child = _core.stop_child


DONE_MARKER = b"VINIX SOUND TEST: GUEST DONE"
FAIL_MARKERS = (
    b"VINIX SOUND TEST: FAIL",
    b"SOUND TEST FAIL line",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)
GUEST_MARKERS = (
    b"virtio-snd: stream 0",
    b"SOUND TEST PASS: OSS parameters",
    b"SOUND TEST PASS: the device has one owner at a time",
    b"SOUND TEST PASS: handled signals do not interrupt writes",
    b"SOUND TEST PASS: writes are paced by playback",
    b"SOUND TEST PASS: a blocked writer can be killed",
    b"SOUND TEST PASS: reopened at another rate",
)


def boot(root: Path, guest_init: Path, initramfs: Path, state: Path, wav: Path,
         timeout: int, no_build: bool) -> bytes | None:
    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(initramfs)
    environment["VINIX_BOOT_DISK"] = str(state / "boot.img")
    environment["VINIX_EFIVARS"] = str(state / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(state / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(state / "root.ext2")
    environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "64"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment["VINIX_QEMU_AUDIO"] = f"wav:{wav}"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [str(root / "run-aarch64.sh"), "--serial", "--mem=2048",
               f"--guest-init={guest_init}"]
    if no_build:
        command.insert(1, "--no-build")

    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    status: int | None = None
    shutdown_deadline: float | None = None
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            waited, child_status = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                status = child_status
                break
            readable, _, _ = select.select([master], [], [], 0.25)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                transcript.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            recent = bytes(transcript[-65536:])
            finished = DONE_MARKER in recent or any(m in recent for m in FAIL_MARKERS)
            if finished and shutdown_deadline is None:
                # Quitting through the monitor lets QEMU finish the WAV header.
                os.write(master, b"\x01x")
                shutdown_deadline = time.monotonic() + 10
            if shutdown_deadline is not None and time.monotonic() >= shutdown_deadline:
                break
    finally:
        if status is None:
            stop_child(pid, master)
        os.close(master)
    if status is not None and exit_code(status) != 0:
        print(f"ERROR: VM runner exited with {exit_code(status)}", file=sys.stderr)
    return bytes(transcript)


def read_wav(path: Path) -> tuple[int, int, list[int]]:
    """Returns rate, channels and the first channel's samples.

    Parsed by hand because a VM that did not shut down cleanly leaves the
    header's sizes at zero while the samples are all there."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV file")
    offset = 12
    rate = channels = bits = 0
    while offset + 8 <= len(data):
        kind = data[offset:offset + 4]
        size = int.from_bytes(data[offset + 4:offset + 8], "little")
        body = offset + 8
        if kind == b"fmt ":
            channels = int.from_bytes(data[body + 2:body + 4], "little")
            rate = int.from_bytes(data[body + 4:body + 8], "little")
            bits = int.from_bytes(data[body + 14:body + 16], "little")
        elif kind == b"data":
            if size == 0 or body + size > len(data):
                size = len(data) - body
            if bits != 16:
                raise ValueError(f"unexpected {bits}-bit WAV")
            frame = 2 * channels
            pcm = data[body:body + size - size % frame]
            samples = [int.from_bytes(pcm[i:i + 2], "little", signed=True)
                       for i in range(0, len(pcm), frame)]
            return rate, channels, samples
        offset = body + size + (size & 1)
    raise ValueError("WAV has no data chunk")


def window_frequency(segment: list[int], rate: int) -> float:
    """Frequency from the first and last rising zero crossings, placed
    between samples by interpolation so that a 25 ms window is enough."""
    crossings = [i + a / (a - b) for i, (a, b) in enumerate(zip(segment, segment[1:]))
                 if a < 0 <= b]
    if len(crossings) < 2:
        return 0.0
    return (len(crossings) - 1) * rate / (crossings[-1] - crossings[0])


def check_recording(wav: Path) -> list[str]:
    try:
        rate, channels, samples = read_wav(wav)
    except (OSError, ValueError) as error:
        return [f"cannot read the recording {wav}: {error}"]
    print(f"==> Recorded {len(samples) / rate:.2f} s at {rate} Hz, {channels} channels")

    # QEMU records only while a voice plays, so the tones arrive back to back
    # and are told apart by pitch. Silence inside the sound is an underrun.
    problems = []
    quiet = rate // 200
    first = last = None
    dropouts = 0
    for start in range(0, len(samples) - quiet + 1, quiet):
        if max(abs(s) for s in samples[start:start + quiet]) > 1000:
            if first is None:
                first = start
            elif last is not None and start - last > quiet:
                dropouts += 1
            last = start
    if first is None:
        return ["the recording is silent"]
    if dropouts:
        problems.append(f"{dropouts} dropouts inside the sound")

    window = rate // 40
    runs: list[list] = []
    for start in range(first, last + quiet - window + 1, window):
        hz = window_frequency(samples[start:start + window], rate)
        label = next((f for f in (440.0, 660.0, 880.0) if abs(hz - f) < f * 0.03), None)
        if runs and runs[-1][0] == label:
            runs[-1][1] += 1
        else:
            runs.append([label, 1])
    tones = [(label, count * window / rate) for label, count in runs if label]
    stray = sum(count for label, count in runs if not label)
    for label, length in tones:
        print(f"    {label:.0f} Hz for {length:.3f} s")
    if stray > 3:
        problems.append(f"{stray} windows matched no tone")
    # The killed writer's tone lasts as long as it ran plus what the device
    # still held, so it only has to be there.
    expected = [(440.0, 2.0, 0.06), (660.0, 0.45, 0.25), (880.0, 0.5, 0.06)]
    if [label for label, _ in tones] != [label for label, _, _ in expected]:
        problems.append(f"heard {tones}, expected {expected}")
    else:
        for (label, length), (_, want, slack) in zip(tones, expected):
            if abs(length - want) > slack:
                problems.append(f"{label:.0f} Hz lasted {length:.3f} s, expected {want}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--init", type=Path, required=True)
    parser.add_argument("--initramfs", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2],
                        help="checkout whose run-aarch64.sh and kernel to boot")
    parser.add_argument("--no-build", action="store_true")
    arguments = parser.parse_args()

    state = arguments.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    wav = state / "sound.wav"
    print("==> Starting AArch64 QEMU sound boot")
    output = boot(arguments.root.absolute(), arguments.init.resolve(),
                  arguments.initramfs.resolve(), state, wav,
                  arguments.timeout, arguments.no_build)

    problems = [f"missing guest result: {m.decode()}" for m in (*GUEST_MARKERS, DONE_MARKER)
                if m not in output]
    problems += [f"guest failure: {m.decode()}" for m in FAIL_MARKERS if m in output]
    if not problems:
        problems = check_recording(wav)
    for problem in problems:
        print(f"ERROR: {problem}", file=sys.stderr)
    if problems:
        return 1
    print("==> AArch64 QEMU sound regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
