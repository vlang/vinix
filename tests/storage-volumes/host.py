#!/usr/bin/env python3
"""Run the unchanged volume, metrics and extent-reservation code on the host."""
from contextlib import nullcontext
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    context = nullcontext(os.environ['VINIX_VOLUME_HOST_DIR']) if os.environ.get('VINIX_VOLUME_HOST_DIR') else tempfile.TemporaryDirectory(prefix='vinix-volume-host-')
    with context as directory:
        work = Path(directory)
        def put(path, text):
            p = work / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
        for source in ['kernel/fs/storage_control.v', 'kernel/resource/block_status.v', 'kernel/resource/block_discard.v',
                       'kernel/resource/block_identity.v', 'kernel/security/device_policy.v']:
            target = work / '/'.join(source.split('/')[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / source, target)
        put('v.mod', "Module { name: 'volume_host' }\n")
        put('kbudget/budget.v', '''@[has_globals]
module kbudget
__global (pub host_budget_live i64 pub host_budget_deny bool)
pub struct Charge { pub: bytes u64 }
pub enum Kind { file }
pub fn reserve(bytes u64) ?Charge { if host_budget_deny { return none }; host_budget_live += i64(bytes); return Charge{bytes:bytes} }
pub fn release(charge Charge) { host_budget_live -= i64(charge.bytes) }
''')
        put('klock/lock.v', 'module klock\npub struct Lock {}\npub fn (mut l Lock) acquire() {}\npub fn (mut l Lock) release() {}\n')
        put('event/eventstruct/event.v', 'module eventstruct\npub struct Event {}\n')
        put('stat/stat.v', '''module stat
pub const ifblk = u32(0o60000)
pub struct Stat { pub mut: size i64 blksize i64 blocks i64 mode u32 rdev u64 nlink u64 }
pub fn isblk(mode u32) bool { return mode & 0o170000 == ifblk }
''')
        put('errno/errno.v', '''@[has_globals]
module errno
__global host_errno_code int
pub const eperm=1
pub const eintr=4
pub const eio=5
pub const ebadf=9
pub const enomem=12
pub const efault=14
pub const ebusy=16
pub const eexist=17
pub const enodev=19
pub const einval=22
pub const enotty=25
pub const enospc=28
pub const erofs=30
pub const eoverflow=75
pub const eopnotsupp=95
pub fn set(value int) { host_errno_code=value }
pub fn get() int { return host_errno_code }
''')
        put('katomic/atomic.v', '''module katomic
pub fn load[T](v &T) T { return unsafe { *v } }
pub fn cas[T](mut v T, before T, after T) bool { if v!=before { return false }; v=after; return true }
pub fn inc[T](mut v T) T { old:=v; v++; return old }
pub fn dec[T](mut v T) bool { v--; remaining:=v; return remaining!=0 }
''')
        put('memory/memory.v', '''@[has_globals]
module memory
__global (pub live int pub left int = -1)
pub fn user_address_limit() u64 { return 0 }
pub fn malloc_packed_fallible(size u64) voidptr {
 if left==0 { return unsafe { nil } }; if left>0 { left-- }
 p:=unsafe { C.malloc(size) }; if p!=unsafe { nil } { live++ }; return p
}
pub fn calloc(size u64, count u64) voidptr { p:=malloc_packed_fallible(size*count); if p!=unsafe { nil } { unsafe { C.memset(p,0,size*count) } }; return p }
pub fn free(p voidptr) { if p!=unsafe { nil } { live--; unsafe { C.free(p) } } }
''')
        put('usercopy/copy.v', '''module usercopy
pub fn copy_from_user(to voidptr, from u64, bytes u64) bool { if from==0 { return false }; unsafe { C.memcpy(to,voidptr(from),bytes) }; return true }
pub fn copy_to_user(to u64, from voidptr, bytes u64) bool { if to==0 { return false }; unsafe { C.memcpy(voidptr(to),from,bytes) }; return true }
''')
        put('proc/proc.v', '''@[has_globals]
module proc
import kbudget
pub fn reserve_kernel(_ kbudget.Kind, bytes u64) ?kbudget.Charge { return kbudget.reserve(bytes) }
pub const cap_sys_admin=21
pub const mac_read=u64(1)
pub const mac_write=u64(2)
__global pub admin bool = true
pub struct Namespace { pub: user voidptr }
pub struct Process { pub: ns Namespace exiting bool }
pub struct Thread { pub: process Process masked_signals u64 must_exit bool }
__global thread Thread
pub fn current_thread() &Thread { return &thread }
pub fn mac_trusted() bool { return admin }
pub fn is_initial_namespace(_ voidptr) bool { return true }
pub fn has_capability(_ Process, _ int) bool { return admin }
pub fn pending_signals(_ &Thread) u64 { return 0 }
pub fn host_cancel(cancel bool) { thread = Thread{must_exit: cancel} }
''')
        put('sched/sched.v', '@[has_globals]\nmodule sched\n__global pub host_yield_hook = fn () {}\npub fn yield(_ bool) { host_yield_hook() }\n')
        put('resource/base.v', '''module resource
import stat
import klock
import event.eventstruct
import katomic
import errno
#define vinix_stack_alloc __builtin_alloca
fn C.vinix_stack_alloc(usize) voidptr
pub const o_rdonly=0
pub const o_wronly=1
pub const o_rdwr=2
pub const o_path=0o10000000
pub const o_accmode=3|o_path
pub interface Resource { mut:
 stat stat.Stat refcount int l klock.Lock event eventstruct.Event status int can_mmap bool
 grow(voidptr,u64) ?
 read(voidptr,voidptr,u64,u64) ?i64
 write(voidptr,voidptr,u64,u64) ?i64
 ioctl(voidptr,u64,voidptr) ?int
 unref(voidptr) ?
 link(voidptr) ?
 unlink(voidptr) ?
 mmap(voidptr,u64,int) voidptr
}
pub interface SyncableResource { mut: sync(voidptr) ? }
pub interface ReadOnlyResource { read_only_backend() bool }
pub fn retain_resource(mut r Resource) { katomic.inc(mut &r.refcount) }
pub fn release_resource(mut r Resource) { r.unref(unsafe { nil }) or {} }
pub fn sync_resource(mut r Resource, h voidptr) ? { if mut r is SyncableResource { r.sync(h)? } }
pub fn default_ioctl(_ voidptr,_ u64,_ voidptr) ?int { errno.set(errno.enotty); return none }
pub fn create_dev_id() u64 { return 1 }
''')
        put('file/file.v', '''module file
import resource
pub struct Handle { pub mut: resource &resource.Resource flags int }
pub fn (mut h Handle) mac_check(_ u64) ? {}
pub struct FD { pub mut: handle &Handle }
''')
        put('security/host_helpers.v', 'module security\npub fn host_policy_rows() int { return block_device_policies.len }\n')
        put('security/level.v', '''@[has_globals]
module security
__global pub host_securelevel int
pub fn securelevel() int { return host_securelevel }
''')
        put('fs/stubs.v', '''@[has_globals]
module fs
import memory
import resource
__global (nodes [64]&resource.Resource reject_publication bool)
pub fn devtmpfs_add_volume(r &resource.Resource, _ string) ? { if reject_publication { return none }; for i in 0..64 { if nodes[i]==unsafe { nil } { nodes[i]=r; return } }; return none }
fn security_register(mut r resource.Resource) { security.register_block_device(resource.block_identity(mut r)) }
pub fn devtmpfs_remove_device(_ string, r &resource.Resource) bool { for i in 0..64 { if nodes[i]==r { nodes[i]=unsafe { nil }; mut actual:=unsafe { r }; resource.release_resource(mut actual); return true } }; return false }
pub fn free_after_grace(p voidptr) { memory.free(p) }
pub fn free_charged_after_grace(p voidptr, charge kbudget.Charge) { memory.free(p); kbudget.release(charge) }
pub fn release_resource_after_grace(r &resource.Resource) { mut actual:=unsafe { r }; resource.release_resource(mut actual) }
'''.replace('import resource\n','import resource\nimport security\nimport kbudget\n'))
        shutil.copyfile(ROOT / 'tests/storage-volumes/volume_test.v', work / 'fs/volume_test.v')
        command = [os.environ.get('V', 'v'), '-enable-globals', '-cc', 'clang']
        if os.environ.get('VINIX_HOST_SANITIZE') == '1':
            command += ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
        subprocess.run(command + ['test', 'fs'], cwd=work, check=True,
                       env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})


if __name__ == '__main__': main()
