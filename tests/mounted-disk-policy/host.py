#!/usr/bin/env python3
"""Exercise the production scalar policy with host-only locks and device fixtures."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

STUBS = {
    "stat/stat.v": """module stat
pub struct Stat {
pub mut:
 mode u32
 rdev u64
 size i64
}
pub fn isblk(mode u32) bool { return mode & 0o170000 == 0o060000 }
""",
    "errno/errno.v": """@[has_globals]
module errno
__global ( saved int )
pub const eperm = 1
pub const enodev = 19
pub const ebusy = 16
pub const eoverflow = 75
pub fn set(value int) { saved = value }
pub fn get() int { return saved }
""",
    "klock/klock.v": """module klock
fn C.host_lock(voidptr)
fn C.host_unlock(voidptr)
pub struct Lock {
pub mut:
 cell bool
}
pub fn (mut guard Lock) acquire() { C.host_lock(&guard.cell) }
pub fn (mut guard Lock) release() { C.host_unlock(&guard.cell) }
""",
    "resource/stub.v": """module resource
import stat
fn C.vinix_stack_alloc(usize) voidptr
pub interface Resource {
mut:
 stat stat.Stat
}
""",
    "security/level.v": """@[has_globals]
module security
__global ( current_level int )
pub fn securelevel() int { return current_level }
pub fn set_level(value int) { current_level = value }
""",
}

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

MAIN = r"""
module main
import resource
import security
import stat
import errno
fn C.host_signal_started()
fn C.host_wait_started()
fn C.host_signal_release()
fn C.host_wait_release()
struct Hardware {
pub mut:
 stat stat.Stat
 identity resource.BlockIdentity
}
fn (device &Hardware) block_identity() resource.BlockIdentity { return device.identity }
struct Fake {
pub mut:
 stat stat.Stat
}
fn device(identity resource.BlockIdentity, mode u32) resource.Resource {
    return Hardware{stat: stat.Stat{mode: mode, rdev: identity.disk_id, size: i64(identity.length)}, identity: identity}
}
fn hold_raw_write(disk &resource.Resource) {
    mut actual := unsafe { disk }
    token := security.begin_user_device_write(mut actual) or { panic('writer should start insecure') }
    C.host_signal_started()
    C.host_wait_release()
    security.end_user_device_write(token)
}
fn main() {
    whole := resource.BlockIdentity{is_block: true, disk_id: 1, length: 1048576}
    volume := resource.BlockIdentity{is_block: true, disk_id: 1, start: 16384, length: 65536}
    sibling := resource.BlockIdentity{is_block: true, disk_id: 1, start: 131072, length: 65536}
    overlap := resource.BlockIdentity{is_block: true, disk_id: 1, start: 32768, length: 65536}
    other := resource.BlockIdentity{is_block: true, disk_id: 2, length: 1048576}
    assert volume.overlaps(whole) && whole.overlaps(volume)
    assert volume.overlaps(overlap) && !volume.overlaps(sibling) && !volume.overlaps(other)
    assert !resource.BlockIdentity{is_block: true, disk_id: 1, start: u64(-16), length: 32}.valid()
    assert !resource.BlockIdentity{is_block: true, disk_id: 1, length: 0}.valid()
    for identity in [whole, volume, sibling, overlap, other] { security.register_block_device(identity) }
    mut disk := device(whole, 0o060000)
    mut part := device(volume, 0o060000)
    mut neighbor := device(sibling, 0o060000)
    mut spare := device(other, 0o060000)
    mut alias := device(whole, 0o020000) // Caller mode cannot change real backing provenance.
    mut fake := resource.Resource(Fake{stat: stat.Stat{mode: 0o060000, rdev: 1, size: 1048576}})
    assert !resource.block_identity(mut fake).valid()
    security.set_level(0)
    writer := spawn hold_raw_write(&disk)
    C.host_wait_started()
    security.set_level(1)
    token := security.begin_block_mount(volume) or {
        assert errno.get() == errno.ebusy
        -1
    }
    assert token == -1
    // Growing the inventory while a writer sleeps cannot invalidate its token.
    for id in 3 .. 300 { security.register_block_device(resource.BlockIdentity{is_block: true, disk_id: u64(id), length: 4096}) }
    C.host_signal_release()
    writer.wait()
    reserved := security.begin_block_mount(volume) or { panic('completed writer must release reservation conflict') }
    assert !security.user_device_write_allowed(mut disk)
    assert !security.user_device_write_allowed(mut part)
    assert security.user_device_write_allowed(mut neighbor) && security.user_device_write_allowed(mut spare)
    security.finish_block_mount(reserved, false)
    assert security.user_device_write_allowed(mut disk) // Failed mount cancels protection.
    cancelled := security.begin_user_device_write(mut part) or { panic('cancelled mount should permit raw writes') }
    security.end_user_device_write(cancelled)
    committed := security.begin_block_mount(volume) or { panic('mount should reserve') }
    security.finish_block_mount(committed, true)
    for _ in 0 .. 10000 {
        assert !security.user_device_write_allowed(mut alias)
        denial := security.begin_user_device_write(mut disk) or { assert errno.get() == errno.eperm; -1 }
        assert denial == -1
    }
    assert !security.user_device_write_allowed(mut fake)
    allowed := security.begin_user_device_write(mut neighbor) or { panic('non-overlap must stay writable') }
    security.end_user_device_write(allowed)
    allowed_other := security.begin_user_device_write(mut spare) or { panic('unrelated disk must stay writable') }
    security.end_user_device_write(allowed_other)
    security.set_level(2)
    assert !security.user_device_write_allowed(mut spare) && !security.user_device_write_allowed(mut alias)
    security.set_level(0)
    assert security.user_device_write_allowed(mut disk)
    println('PASS: production topology, provenance, mount/write interleaving, cancellation, inventory growth and securelevels')
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix="vinix-block-policy-host-") as directory:
        work = Path(directory)
        for relative, content in STUBS.items():
            target = work / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative in ("klock/klock.v", "resource/stub.v"):
                content = content.replace("module " + relative.split("/")[0], "module " + relative.split("/")[0] + f'\n#flag -I{work}\n#include "host.h"')
            target.write_text(content)
        shutil.copy2(ROOT / "kernel/resource/block_identity.v", work / "resource/block_identity.v")
        shutil.copy2(ROOT / "kernel/security/device_policy.v", work / "security/device_policy.v")
        (work / "host.h").write_text(HEADER)
        (work / "main.v").write_text(MAIN.replace("module main", f'module main\n#flag -I{work}\n#include "host.h"'))
        (work / "v.mod").write_text("Module { name: 'blockpolicy_host' }\n")
        binary = work / "test"
        subprocess.run([os.environ.get("V", "v"), "-enable-globals", "-gc", "none", "-cc", "clang",
            "-cflags", "-fsanitize=address,undefined", "-ldflags", "-fsanitize=address,undefined",
            "-o", str(binary), str(work)], check=True)
        subprocess.run([str(binary)], env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0"}, check=True, timeout=30)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
