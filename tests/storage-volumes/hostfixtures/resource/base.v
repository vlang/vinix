module resource
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
