
@[has_globals]
module main
import katomic
import proc
const max_preemption_cpus = 256
struct Local { mut: cpu_number u64 online u64 = 1 is_idle bool }
__global (
    cpu_locals []&Local
    cpu_dispatch_rank [max_preemption_cpus]int
    cpu_dispatch_deadline [max_preemption_cpus]u64
    cpu_reschedule_pending [max_preemption_cpus]u32
    attempts int
    destination u64
    sends_succeed bool = true
)
fn may_run_here(t &proc.Thread, cpu u64) bool {
    return t.affinity_mask & (u64(1) << cpu) != 0
}
fn capacity_preferred(t &proc.Thread, number u64) bool { return true }
fn send_reschedule(number u64) bool {
    attempts++
    destination = number
    return sends_succeed
}
