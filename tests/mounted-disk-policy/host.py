#!/usr/bin/env python3
"""Exercise the production scalar policy with host-only locks and device fixtures."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


HEADER = r"""
#ifndef VINIX_HOST_BLOCK_POLICY_H
#define VINIX_HOST_BLOCK_POLICY_H
#include <stdbool.h>
#include <stdatomic.h>
#include <unistd.h>
#define vinix_stack_alloc __builtin_alloca
static _Atomic int host_entered, host_released;
static void host_lock(bool *cell) { while (__atomic_exchange_n(cell, true, __ATOMIC_ACQUIRE)) {} }
static void host_unlock(bool *cell) { __atomic_store_n(cell, false, __ATOMIC_RELEASE); }
static void host_signal_started(void) { atomic_store(&host_entered, 1); }
static void host_wait_started(void) { while (!atomic_load(&host_entered)) usleep(1000); }
static void host_signal_release(void) { atomic_store(&host_released, 1); }
static void host_wait_release(void) { while (!atomic_load(&host_released)) usleep(1000); }
#endif
"""



def main():
    with tempfile.TemporaryDirectory(prefix="vinix-block-policy-host-") as directory:
        work = Path(directory)
        generator = os.environ.get("VINIX_BLOCK_POLICY_GENERATOR")
        if not generator:
            generator = str(work / "generator")
            subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                            str(Path(__file__).with_name("host_generator.v")),
                            "--install", generator], check=True)
        subprocess.run([generator, "--stubs", str(work)], check=True)
        shutil.copy2(ROOT / "kernel/resource/block_identity.v", work / "resource/block_identity.v")
        shutil.copy2(ROOT / "kernel/security/device_policy.v", work / "security/device_policy.v")
        (work / "host.h").write_text(HEADER)
        subprocess.run([generator, "--finish", str(work)], check=True)
        binary = work / "test"
        subprocess.run([os.environ.get("V", "v"), "-enable-globals", "-gc", "none", "-cc", "clang",
            "-cflags", "-fsanitize=address,undefined", "-ldflags", "-fsanitize=address,undefined",
            "-o", str(binary), str(work)], check=True)
        subprocess.run([str(binary)], env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0"}, check=True, timeout=30)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
