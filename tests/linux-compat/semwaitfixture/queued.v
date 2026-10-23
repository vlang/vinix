// Private UNBUILT synchronous-grant semantic controls; no qualification claim.
module semwaitfixture

fn queued_competition(mut totals Totals) {
	unsafe {
		id := create([i32(0), 0, 0]!)
		a := start(id, one(0, -1), 1, -1)
		b := start(id, one(0, -1), 1, -1)
		storage_nonblocking(a)
		storage_nonblocking(b)
		first := &OutcomeReader(C.alloca(sizeof(OutcomeReader)))
		second := &OutcomeReader(C.alloca(sizeof(OutcomeReader)))
		*first = OutcomeReader{}
		*second = OutcomeReader{}
		counts := &LifecycleCounts(C.alloca(sizeof(LifecycleCounts)))
		*counts = LifecycleCounts{}
		check(mut totals, storage_await_sleep(a, first), 600)
		check(mut totals, storage_await_sleep(b, second), 601)
		await_grid(id, [i32(2), 0, 0]!, [i32(0), 0, 0]!, mut totals, 602)
		set_value(id, 0, 1)
		// One unit must be granted synchronously, with one waiter left. Do
		// not presume which child won: readiness did not order queue entry.
		check(mut totals, grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!), 603)
		values(id, [i32(0), 0, 0]!, mut totals, 604)
		mut first_done := false
		mut second_done := false
		for _ in 0 .. 2000 {
			first_done = storage_read(a, first)
			second_done = storage_read(b, second)
			if first_done || second_done { break }
			C.usleep(1000)
		}
		check(mut totals, first_done != second_done, 607)
		check(mut totals, grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!), 608)
		values(id, [i32(0), 0, 0]!, mut totals, 609)
		set_value(id, 0, 1)
		storage_finish(a, first, 0, mut totals, counts)
		storage_finish(b, second, 0, mut totals, counts)
		empty(id, mut totals, 612)
		values(id, [i32(0), 0, 0]!, mut totals, 613)
		remove(id)
	}
}

fn queued_dependencies(mut totals Totals) {
	unsafe {
		id := create([i32(0), 0, 0]!)
		// Queue the dependent vector first. A forward scan initially skips
		// it, then granting the later vector enables it, requiring a rescan.
		dependent_ops := [SemOp{ number: 1, adjustment: -1 }, SemOp{ number: 2, adjustment: 1 }, SemOp{}]!
		grant_ops := [SemOp{ adjustment: -1 }, SemOp{ number: 1, adjustment: 1 }, SemOp{}]!
		dependent := start(id, dependent_ops, 2, -1)
		storage_nonblocking(dependent)
		first := &OutcomeReader(C.alloca(sizeof(OutcomeReader)))
		second := &OutcomeReader(C.alloca(sizeof(OutcomeReader)))
		*first = OutcomeReader{}
		*second = OutcomeReader{}
		counts := &LifecycleCounts(C.alloca(sizeof(LifecycleCounts)))
		*counts = LifecycleCounts{}
		check(mut totals, storage_await_sleep(dependent, first), 620)
		await_grid(id, [i32(0), 1, 0]!, [i32(0), 0, 0]!, mut totals, 621)
		grant := start(id, grant_ops, 2, -1)
		storage_nonblocking(grant)
		check(mut totals, storage_await_sleep(grant, second), 622)
		await_grid(id, [i32(1), 1, 0]!, [i32(0), 0, 0]!, mut totals, 623)
		set_value(id, 0, 1)
		check(mut totals, grid(id, [i32(0), 0, 0]!, [i32(0), 0, 0]!), 624)
		values(id, [i32(0), 0, 1]!, mut totals, 625)
		storage_finish(grant, second, 0, mut totals, counts)
		storage_finish(dependent, first, 0, mut totals, counts)
		empty(id, mut totals, 628)
		values(id, [i32(0), 0, 1]!, mut totals, 629)
		remove(id)
	}
}
