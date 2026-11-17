@[has_globals]
module fw
__global fail_context bool
__global fail_notifier bool
pub struct G13GpuContextData { data [64]u8 }
pub struct ListHead { pub mut: next u64 }
pub struct G13NotifierList { pub mut: list_head ListHead }
pub fn validate_g13_workqueue_layouts() bool { return true }
pub fn validate_g13_event_layouts() bool { return true }
pub fn initialize_g13_gpu_context(_ voidptr, _ u64) bool { return !fail_context }
pub fn initialize_g13_notifier(_ voidptr, _ u64, _ int, _ u64, _ u32) bool { return !fail_notifier }
pub fn g13_notifier_active_size(_ int) ?u64 { return 64 }
pub fn configure(context bool, notifier bool) { fail_context = context; fail_notifier = notifier }
