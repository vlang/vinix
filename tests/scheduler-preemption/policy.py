#!/usr/bin/env python3
"""Exercise production enqueue target selection with synthetic CPU snapshots."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "kernel/sched/preemption.v").read_text()


def function(name):
    start = source.index(f"fn {name}(")
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


program = """
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
"""
for name in ("enqueue_outranks", "request_enqueue_preemption", "consume_reschedule"):
    program += function(name)
program += """
fn main() {
    cpu_locals = [&Local{cpu_number: 0, is_idle: true},
                 &Local{cpu_number: 1}, &Local{cpu_number: 2}]
    cpu_dispatch_rank[1] = 1
    cpu_dispatch_rank[2] = 150
    mut t := proc.Thread{affinity_mask: 2, sched: proc.SchedParams{urgency: 150}}
    request_enqueue_preemption(&t)
    assert attempts == 1 && destination == 1
    request_enqueue_preemption(&t)
    assert attempts == 1 // coalesced until a scheduling boundary
    consume_reschedule(1)
    request_enqueue_preemption(&t)
    assert attempts == 2
    consume_reschedule(1)

    t.affinity_mask = 6
    cpu_locals[2].is_idle = true
    request_enqueue_preemption(&t)
    assert attempts == 3 && destination == 2 // prefer eligible idle CPU
    consume_reschedule(2)
    cpu_locals[2].is_idle = false
    t.sched.urgency = 1
    request_enqueue_preemption(&t)
    assert attempts == 3 // equal normal rank does not preempt by enqueue
    t.sched.urgency = 150
    cpu_locals[1].online = 0
    request_enqueue_preemption(&t)
    assert attempts == 3 // offline and equal-priority CPUs are excluded

    t.sched.urgency = 200
    t.sched.dl_abs_deadline = 100
    cpu_dispatch_rank[2] = 200
    cpu_dispatch_deadline[2] = 90
    request_enqueue_preemption(&t)
    assert attempts == 3 // later deadline cannot interrupt an earlier one
    cpu_dispatch_deadline[2] = 120
    request_enqueue_preemption(&t)
    assert attempts == 4 && destination == 2
    consume_reschedule(2)

    sends_succeed = false
    request_enqueue_preemption(&t)
    request_enqueue_preemption(&t)
    assert attempts == 6 // unavailable controller must not leave pending set
    assert cpu_reschedule_pending[2] == 0
    assert !enqueue_outranks(150, 0, 150, 0) // equal FIFO priority
    assert enqueue_outranks(1, 0, 0, 0) // ordinary work interrupts SCHED_IDLE
    println('Scheduler enqueue policy: PASS')
}
"""
with tempfile.TemporaryDirectory(prefix="vinix-enqueue-policy-") as directory:
    path = Path(directory)
    (path / "v.mod").write_text("Module { name: 'preemption_test' }\n")
    (path / "main.v").write_text(program)
    (path / "proc").mkdir()
    (path / "proc/proc.v").write_text("""
module proc
pub const rank_deadline = 200
pub struct SchedParams { pub mut: urgency int dl_abs_deadline u64 }
pub fn (s &SchedParams) rank() int { return s.urgency }
pub struct Thread { pub mut: sched SchedParams affinity_mask u64 }
pub fn effective_sched_rank(t &Thread) int { return t.sched.rank() }
""")
    (path / "katomic").mkdir()
    (path / "katomic/katomic.v").write_text("""
module katomic
pub fn load[T](here &T) T { return *here }
pub fn store[T](mut here T, value T) {
    unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) }
}
pub fn cas[T](mut here T, previous T, value T) bool {
    if unsafe { C.memcmp(voidptr(here), &previous, sizeof(T)) } != 0 { return false }
    unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) }
    return true
}
""")
    subprocess.run([os.environ.get("V", "v"), "-enable-globals", "run", str(path)], check=True)
