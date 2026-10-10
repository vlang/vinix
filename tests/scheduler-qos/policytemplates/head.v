@[has_globals]
module main
import proc
import katomic
import errno
import klock
const max_runqueue_cpus = 256
struct RunQueue { mut: count u64 }
struct Local { mut: cpu_number u64 online u64 = 1 is_idle bool = true }
__global (cpu_locals []&Local runqueues [256]RunQueue cpu_capacities [256]u32)
fn may_run_here(t &proc.Thread, cpu u64) bool { return t.affinity_mask & (u64(1) << cpu) != 0 }
