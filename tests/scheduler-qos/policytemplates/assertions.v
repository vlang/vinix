
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
