
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
