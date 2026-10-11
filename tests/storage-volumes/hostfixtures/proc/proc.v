@[has_globals]
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
