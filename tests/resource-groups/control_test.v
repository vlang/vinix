module cgcontrol

fn competing_tasks(group &Group) {
	for _ in 0 .. 20000 {
		if reserve(group, 0, 1) { release(group, 0, 1) }
	}
}

fn test_hierarchical_admission_migration_and_recovery() {
	mut parent := Group{pids_max: 4, memory_max: 1000}
	mut left := Group{parent: unsafe { &parent }, pids_max: 3}
	mut right := Group{parent: unsafe { &parent }, pids_max: 3}
	assert reserve(unsafe { &left }, 200, 3)
	assert !reserve(unsafe { &left }, 1, 1)
	assert reserve(unsafe { &right }, 300, 1)
	assert !reserve(unsafe { &right }, 1, 1)
	assert snapshot(unsafe { &parent }).pids == 4
	assert move(unsafe { &left }, unsafe { &right }, 100, 1)
	assert snapshot(unsafe { &parent }).pids == 4
	assert snapshot(unsafe { &parent }).kernel == 500
	assert !move(unsafe { &left }, unsafe { &right }, 100, 2)
	assert snapshot(unsafe { &left }).pids == 2
	assert snapshot(unsafe { &right }).pids == 2
	assert !reserve(unsafe { &left }, 501, 0)
	release(unsafe { &left }, 100, 2)
	release(unsafe { &right }, 400, 2)
	assert snapshot(unsafe { &parent }).kernel == 0
	mut workers := []thread{}
	for _ in 0 .. 24 { workers << spawn competing_tasks(unsafe { &right }) }
	workers.wait()
	assert snapshot(unsafe { &parent }).pids == 0
	assert snapshot(unsafe { &parent }).pids_peak <= 4
	assert snapshot(unsafe { &right }).pids_peak <= 3
	assert snapshot(unsafe { &right }).pids_events > 0
	set_pids_max(mut parent, 0)
	assert !reserve(unsafe { &right }, 0, 1)
	set_pids_max(mut parent, 4)
	assert reserve(unsafe { &right }, 0, 1)
	release(unsafe { &right }, 0, 1)
	set_memory_limits(mut parent, 100, true)
	sample_memory(mut parent, 110)
	assert snapshot(unsafe { &parent }).level == 1
	assert reserve(unsafe { &right }, 890, 0)
	assert snapshot(unsafe { &parent }).level == 2
	assert !reserve(unsafe { &right }, 1, 0)
	release(unsafe { &right }, 890, 0)
	sample_memory(mut parent, 0)
	assert snapshot(unsafe { &parent }).level == 0
}

fn test_io_hierarchy_and_overflow() {
	mut parent := Group{}
	mut child := Group{parent: unsafe { &parent }}
	assert set_io(mut parent, Device{id: 7, rbps: 1000, wiops: 4})
	assert set_io(mut child, Device{id: 7, rbps: 2000})
	a, version := account_io(unsafe { &child }, 7, 500, false, 1000000000)
	assert a == 1500000000
	b, _ := account_io(unsafe { &child }, 7, 500, false, 1000000000)
	assert b == 2000000000
	c, _ := account_io(unsafe { &child }, 7, 1, true, 1000000000)
	assert c == 1250000000
	assert snapshot(unsafe { &parent }).io[0].rbytes == 1000
	assert snapshot(unsafe { &parent }).io[0].rios == 2
	assert snapshot(unsafe { &child }).io_events == 2
	assert set_io(mut parent, Device{id: 7})
	assert epoch() != version
	d, _ := account_io(unsafe { &child }, 7, 500, false, 3000000000)
	assert d == 3250000000
	assert decimal('18446744073709551615')? == ~u64(0)
	if _ := decimal('18446744073709551616') { assert false }
	if _ := decimal('-1') { assert false }
	if _ := decimal('1x') { assert false }
	id := dev_id(4095, 1048575)?
	assert dev_major(id) == 4095 && dev_minor(id) == 1048575
	if _ := dev_id(4096, 0) { assert false }
}

fn test_swap_limits_follow_backing_lifetime() {
	mut parent := Group{swap_max: 4096}
	mut child := Group{parent: unsafe { &parent }}
	assert reserve_swap(unsafe { &child }, 4096)
	assert !reserve_swap(unsafe { &child }, 4096)
	assert snapshot(unsafe { &parent }).swap == 4096
	assert snapshot(unsafe { &parent }).swap_events == 1
	release_swap(unsafe { &child }, 4096)
	assert reserve_swap(unsafe { &child }, 4096)
	release_swap(unsafe { &child }, 4096)
	set_swap_max(mut parent, 0)
	assert !reserve_swap(unsafe { &child }, 1)
	set_swap_max(mut parent, ~u64(0))
	assert reserve_swap(unsafe { &child }, 8192)
	release_swap(unsafe { &child }, 8192)
}

fn test_memory_migration_preserves_common_ancestors_and_rolls_back() {
	mut parent := Group{anonymous: 900, memory_max: 1000}
	mut left := Group{parent: unsafe { &parent }, anonymous: 900}
	mut right := Group{parent: unsafe { &parent }, memory_max: 100}
	assert reserve(unsafe { &left }, 100, 1)
	assert !move_workload(unsafe { &left }, unsafe { &right }, 100, 1, 900)
	assert snapshot(unsafe { &left }).anonymous == 900
	assert snapshot(unsafe { &left }).pids == 1
	set_memory_limits(mut right, 1000, false)
	assert move_workload(unsafe { &left }, unsafe { &right }, 100, 1, 900)
	assert snapshot(unsafe { &parent }).anonymous == 900
	assert snapshot(unsafe { &parent }).kernel == 100
	assert snapshot(unsafe { &left }).anonymous == 0
	assert snapshot(unsafe { &right }).anonymous == 900
	release(unsafe { &right }, 100, 1)
	forget_memory(unsafe { &right }, 900)
	assert snapshot(unsafe { &parent }).anonymous == 0
	assert retire(mut right)
	assert !reserve(unsafe { &right }, 0, 1)
}
