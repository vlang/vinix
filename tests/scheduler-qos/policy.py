#!/usr/bin/env python3
"""Exercise production capacity selection, donation graphs and timer deadlines."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def function(source, name):
    start = source.index("fn " + name)
    start = source.rfind("\n", 0, start) + 1
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


with tempfile.TemporaryDirectory(prefix="vinix-scheduler-qos-") as directory:
    path = Path(directory)
    (path / "v.mod").write_text("Module { name: 'scheduler_qos_test' }\n")
    for module, content in {
        "katomic": """module katomic
pub fn load[T](here &T) T { return *here }
pub fn store[T](mut here T, value T) { unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) } }
""",
        "klock": """module klock
pub struct Lock { pub mut: busy bool }
pub fn (mut l Lock) acquire() { assert !l.busy; l.busy = true }
pub fn (mut l Lock) release() { assert l.busy; l.busy = false }
pub fn (mut l Lock) test_and_acquire() bool { if l.busy { return false }; l.busy = true; return true }
""",
        "errno": """@[has_globals]
module errno
pub const edeadlk = 35
pub const eagain = 11
__global (last_error int)
pub fn set(value int) { last_error = value }
pub fn get() int { return last_error }
""",
    }.items():
        (path / module).mkdir()
        (path / module / (module + ".v")).write_text(content)
    priority = (ROOT / "kernel/proc/priority.v").read_text()
    proc = """@[has_globals]
module proc
import katomic
import klock
import errno
const max_priority_donations = 2048
const max_priority_chain = 64
struct PriorityDonation { mut: waiter &Thread = unsafe { nil } owner &Thread = unsafe { nil } }
__global (priority_lock klock.Lock priority_donations [max_priority_donations]PriorityDonation priority_donation_count u64)
pub struct SchedParams { pub mut: urgency int util_min u32 util_max u32 = 1024 }
pub fn (s &SchedParams) rank() int { return s.urgency }
pub struct Thread { pub mut: tid int sched SchedParams pi_rank int pins int affinity_mask u64 = 15 }
pub fn pin_thread(t &Thread) { unsafe { (&Thread(t)).pins++ } }
pub fn unpin_thread(t &Thread) { unsafe { (&Thread(t)).pins-- }; assert t.pins >= 0 }
"""
    for name in ("effective_sched_rank(", "priority_donations_active(", "recompute_donations(",
                 "donate_priority(", "remove_priority_donation(", "retarget_priority_donation(",
                 "refresh_priority_donations("):
        proc += function(priority, name)
    (path / "proc").mkdir()
    (path / "proc/proc.v").write_text(proc)
    source = (ROOT / "kernel/sched/runqueue.v").read_text()
    main = """@[has_globals]
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
"""
    for name in ("cpu_capacity(", "set_cpu_capacity(", "placement_cpu(", "capacity_preferred("):
        main += function(source, name)
    timer_source = (ROOT / "kernel/time/time.v").read_text()
    main += """
struct TimeSpec { mut: tv_sec i64 tv_nsec i64 }
fn (mut t TimeSpec) sub(other TimeSpec) bool {
 if other.tv_nsec > t.tv_nsec { t.tv_sec--; t.tv_nsec += 1000000000 }
 t.tv_nsec -= other.tv_nsec
 t.tv_sec -= other.tv_sec
 return t.tv_sec < 0 || (t.tv_sec == 0 && t.tv_nsec == 0)
}
struct Timer { mut: when TimeSpec index int = -1 fired bool deadline_ns u64 absolute_realtime bool slack_ns u64 }
const clock_type_realtime = 0
__global (timers_lock klock.Lock armed_timers []&Timer fake_now u64 = 1000000000 fake_wall TimeSpec
 deadline_hooks [8]fn () u64 deadline_hooks_len int wake_requests int)
fn monotonic_ns() u64 { return fake_now }
fn clock_now(_ int) ?TimeSpec { return fake_wall }
fn deadline_changed() { wake_requests++ }
"""
    for name in ("(mut this Timer) disarm(", "(mut this Timer) arm(", "timer_deadline(", "next_wakeup_us("):
        main += function(timer_source, name)
    main += """
fn busy_provider() u64 { return 1000000 }
fn main() {
 cpu_locals = [&Local{cpu_number: 0}, &Local{cpu_number: 1}, &Local{cpu_number: 2}, &Local{cpu_number: 3}]
 set_cpu_capacity(0, 512); set_cpu_capacity(1, 512); set_cpu_capacity(2, 1024); set_cpu_capacity(3, 1024)
 mut task := proc.Thread{tid: 0}
 task.sched.util_min = 800
 assert placement_cpu(&task) == 2
 assert !capacity_preferred(&task, 0)
 task.affinity_mask = 3
 assert placement_cpu(&task) < 2 && capacity_preferred(&task, 0) // mandatory affinity beats hints
 task.affinity_mask = 15; task.sched.util_min = 0; task.sched.util_max = 512
 assert placement_cpu(&task) < 2 && !capacity_preferred(&task, 2)
 cpu_locals[0].is_idle = false; cpu_locals[1].is_idle = false
 assert capacity_preferred(&task, 2) // busy preferred cores permit fallback
 cpu_locals[0].online = 0; cpu_locals[1].online = 0
 assert placement_cpu(&task) >= 2
 assert cpu_capacity(9) == 1024 // unknown firmware data
 set_cpu_capacity(2, 0); assert cpu_capacity(2) == 1024
 mut low := proc.Thread{sched: proc.SchedParams{urgency: 110}}
 mut middle := proc.Thread{sched: proc.SchedParams{urgency: 130}}
 mut high := proc.Thread{sched: proc.SchedParams{urgency: 180}}
 a := proc.donate_priority(&middle, &low) or { panic('first donation') }
 b := proc.donate_priority(&high, &middle) or { panic('chain donation') }
 assert proc.effective_sched_rank(&low) == 180 && proc.effective_sched_rank(&middle) == 180
 proc.donate_priority(&low, &high) or { assert errno.get() == errno.edeadlk }
 high.sched.urgency = 190; proc.refresh_priority_donations()
 assert proc.effective_sched_rank(&low) == 190
 proc.remove_priority_donation(b)
 assert proc.effective_sched_rank(&low) == 130 && proc.effective_sched_rank(&middle) == 130
 proc.retarget_priority_donation(a, &high)
 assert proc.effective_sched_rank(&low) == 110 && low.pins == 0
 proc.remove_priority_donation(a)
 assert !proc.priority_donations_active() && low.pins == 0 && middle.pins == 0 && high.pins == 0
 for _ in 0 .. 200 {
   token := proc.donate_priority(&high, &low) or { panic('repeat donation') }
   proc.remove_priority_donation(token)
 }
 assert low.pins == 0 && high.pins == 0
 mut strict := Timer{when: TimeSpec{tv_nsec: 1000000}}
 strict.arm()
 mut merged := Timer{when: TimeSpec{tv_nsec: 800000}, slack_ns: 300000}
 merged.arm()
 assert merged.deadline_ns == strict.deadline_ns && merged.deadline_ns >= fake_now + 800000
 mut unmerged := Timer{when: TimeSpec{tv_nsec: 700000}, slack_ns: 100000}
 unmerged.arm(); assert unmerged.deadline_ns == fake_now + 700000
 assert next_wakeup_us(50000) == 700
 strict.arm(); assert armed_timers.len == 3 // rearm does not duplicate
 unmerged.disarm(); merged.disarm(); strict.disarm()
 assert armed_timers.len == 0 && next_wakeup_us(50000) == 50000
 timers_lock.busy = true; assert next_wakeup_us(50000) == 1000; timers_lock.busy = false
 deadline_hooks[0] = busy_provider; deadline_hooks_len = 1
 assert next_wakeup_us(50000) == 1000
 deadline_hooks_len = 0
 mut absolute := Timer{when: TimeSpec{tv_sec: 9223372036854775807}, absolute_realtime: true}
 absolute.arm(); assert next_wakeup_us(50000) == 50000 // saturates distant wall deadline
 fake_wall = absolute.when; assert next_wakeup_us(50000) == 1
 absolute.disarm()
 println('Scheduler QoS capacity/donation/deadline policy: PASS')
}
"""
    (path / "main.v").write_text(main)
    subprocess.run([os.environ.get("VEXE", os.environ.get("V", "v")), "-enable-globals", "run", str(path)], check=True)
