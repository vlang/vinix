#!/usr/bin/env python3
"""Compare the frozen independent C guest with its V port under sanitizers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL_REVISION = "9f47270ee3c6754312bc09fc74d8f77e2cfe2229"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--cc", default="clang")
    args = parser.parse_args()
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    original = subprocess.check_output(
        ["git", "show", f"{ORIGINAL_REVISION}:tests/hypervisor/guest.c"], cwd=ROOT)
    (state / "original.c").write_bytes(original)
    # Failure diagnostics retain every independent assertion's original line.
    c_lines = [i for i, line in enumerate(original.decode().splitlines(), 1)
               if "CHECK(" in line and not line.startswith("#define")]
    v_lines = [int(x) for x in re.findall(
        r"\bcheck\([^\n]+, (\d+)\)",
        (ROOT / "tests/hypervisor/guestfixture/core.v").read_text())]
    if c_lines != v_lines:
        raise RuntimeError(f"original assertion diagnostics changed: {c_lines} != {v_lines}")
    generate = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["generate_module"]
    generate(ROOT / "tests/hypervisor/modelcore", state / "model.c", "aarch64")
    generate(ROOT / "tests/hypervisor/guestfixture", state / "ported.c", "aarch64")
    flags = [args.cc, "-g", "-O2", "-Wall", "-Wextra", "-Werror",
             "-fno-strict-aliasing", "-fsanitize=address,undefined",
             "-I", str(ROOT / "tests/hypervisor"),
             "-I", str(ROOT / "tests/hypervisor/guestfixture")]
    generated = ["-Wno-unused-function", "-Wno-unused-parameter"]
    subprocess.run(flags + generated + ["-c", str(state / "model.c"),
                                        "-o", str(state / "model.o")], check=True)
    subprocess.run([args.cc, "-c", str(ROOT / "tests/hypervisor/model-ioctl.S"),
                    "-o", str(state / "ioctl.o")], check=True)
    bindings = [f"-D{name}=hv_model_{name}"
                for name in ("open", "pwrite", "ioctl", "read", "close", "pause")]
    for name in ("original", "ported"):
        subprocess.run(flags + (generated if name == "ported" else []) + bindings +
                       [str(state / f"{name}.c"), str(state / "model.o"), str(state / "ioctl.o"),
                        "-o", str(state / name)], check=True)
    results = []
    for case in range(-3, 16):
        env = {**os.environ, "HV_MODEL_CASE": str(case),
               "ASAN_OPTIONS": "detect_stack_use_after_return=1"}
        runs = [subprocess.run([str(state / name)], env=env, capture_output=True,
                               timeout=30) for name in ("original", "ported")]
        expected = 0 if case in (-2, -1, 0) else 1
        if any(run.returncode != expected or run.stderr for run in runs):
            raise RuntimeError(f"case {case}: unexpected status/sanitizer output: {runs}")
        if runs[0].stdout != runs[1].stdout:
            raise RuntimeError(f"case {case}: original/V output differs: {runs}")
        results.append({"case": case, "exit": expected,
                        "stdout": runs[0].stdout.decode()})
    (state / "result.json").write_text(json.dumps({
        "status": "PASS", "original_revision": ORIGINAL_REVISION,
        "original_sha256": hashlib.sha256(original).hexdigest(),
        "assertion_lines": c_lines, "cases": results,
        "scope": "host ABI model; actual VMX entry requires nested VT-x",
    }, indent=2) + "\n")
    print(f"Hypervisor frozen-C/V: PASS ({len(results)} sanitizer cases, all {len(c_lines)} original assertions)")


if __name__ == "__main__":
    main()
