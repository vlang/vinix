#!/usr/bin/env python3
"""Fetch the author's pinned MIT-licensed Tetrade PS1 homebrew release."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
from pathlib import Path
from build import fetch

ROOT = Path(__file__).resolve().parents[2]
VERSION = "1.0"
REVISION = "5155664152162a0dc04dc1f0d4f3c807c1e15388"
RELEASE = f"https://github.com/Logan-Campbell/Tetrade/releases/download/v{VERSION}"
ARTIFACTS = {
    "tetrade.exe": (f"{RELEASE}/tetrade.exe", "1b67678b7b4ab8a2f22b5a6d10090093e2a659189f29936de7d1792a68a2a8d4", 636928),
    "TETRADE_PSX.bin": (f"{RELEASE}/TETRADE_PSX.bin", "2f41feba2023cbdcd9c1c3d4cfc3d8d1a7f1a2de0afea2e7a050b84640d6eaf8", 3196368),
    "TETRADE_PSX.cue": (f"{RELEASE}/TETRADE_PSX.cue", "98cb45d15241900c8459176e833be5edee78120763ac4d91d79d24020b10d67a", 74),
    "TETRADE-LICENSE": (f"https://raw.githubusercontent.com/Logan-Campbell/Tetrade/{REVISION}/LICENSE", "ced947f24012b2a5bb3352db81f3f186058fabe219013d26cdcdd20a7ba6e173", 1070),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ps1/homebrew")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name, (url, digest, size) in ARTIFACTS.items():
        fetch(output / name, url, digest, size)
    if (output / "tetrade.exe").read_bytes()[:8] != b"PS-X EXE":
        raise ValueError("Tetrade executable has no PlayStation EXE header")
    print(f"Verified Tetrade {VERSION} homebrew by Logan Campbell (MIT): {output}")


if __name__ == "__main__":
    main()
