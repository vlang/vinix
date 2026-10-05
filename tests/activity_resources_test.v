// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_activity_resource_cpu_parser_includes_iowait_and_excludes_guest_double_counting() {
	snapshot := activity_resource_cpu_snapshot('cpu  20 5 10 40 5 2 3 4 12 2\ncpu0 10 2 3 20 4 1 1 2\ncpu1 10 3 7 20 1 1 2 2\nintr 25\n')
	assert snapshot.all.valid
	assert snapshot.all.total == 89
	assert snapshot.all.idle == 45
	assert snapshot.count == 2
	assert snapshot.cores[0].total == 43
	assert snapshot.cores[1].total == 46
}

fn test_activity_resource_parsers_reject_truncated_and_overflowing_values() {
	assert !activity_resource_cpu_snapshot('cpu 1 2 x 4\n').all.valid
	assert !activity_resource_cpu_snapshot('cpu 18446744073709551615 1 0 0\n').all.valid
	assert activity_resource_cpu_snapshot('cpu 1 2 3 4\ncpu90 1 2 3 4\n').count == 0
	assert activity_resource_field('disk_read_bytes: 42\nnotdisk_write_bytes: 9\n', 'disk_read_bytes') or { 0 } == 42
	assert activity_resource_field('bad: 18446744073709551616\n', 'bad') == none
	assert activity_resource_field('bad: 42x\n', 'bad') == none
	assert activity_resource_field('other: 8\n', 'bad') == none
}

fn test_activity_resource_rates_use_actual_interval_and_mark_resets_unmeasured() {
	assert activity_resource_rate(1500, 1000, 500) or { -1.0 } == 1000
	assert activity_resource_rate(1000, 1000, 250) or { -1.0 } == 0
	assert activity_resource_rate(9, 10, 1000) == none
	assert activity_resource_rate(2, u64(-1) - 3, 1000) == none
	assert activity_resource_rate(10, 9, 0) == none
	previous := ActivityCpuCounter{total: 100, idle: 50, valid: true}
	assert activity_resource_cpu_percent(ActivityCpuCounter{total: 200, idle: 75, valid: true}, previous) or { -1.0 } == 75
	assert activity_resource_cpu_percent(ActivityCpuCounter{total: 120, idle: 90, valid: true}, previous) == none
	assert activity_resource_cpu_percent(ActivityCpuCounter{total: 90, idle: 60, valid: true}, previous) == none
	assert activity_resource_cpu_percent(ActivityCpuCounter{total: 200, idle: 75, valid: true}, ActivityCpuCounter{}) == none
}

fn test_activity_resource_history_rolls_without_reordering_or_allocating() {
	mut history := ActivityResourceHistory{}
	for i in 0 .. activity_resource_samples + 5 { history.append(f64(i), u64(i * 500), i != 12) }
	assert history.count == activity_resource_samples
	assert history.values[history.index(0)] == 5
	assert history.values[history.index(activity_resource_samples - 1)] == 64
	assert history.times[history.index(0)] == 2500
	assert !history.valid[history.index(7)]
	assert history.latest() == 64
	assert history.available()
	history.append(0, 32500, false)
	assert !history.available()
	history.append(10, 5, true)
	assert history.count == 1
	assert history.latest() == 10
	assert history.times[history.index(0)] == 5
}

fn test_activity_resource_tabs_and_core_pages_have_working_actions() {
	mut resources := ActivityResources{}
	assert resources.handle('activity.resources.memory')
	assert resources.tab == .memory
	assert resources.handle('activity.resources.disk')
	assert resources.tab == .disk
	assert resources.handle('activity.resources.network')
	assert resources.tab == .network
	assert resources.handle('activity.resources.cpu')
	assert resources.tab == .cpu
	assert resources.handle('activity.resources.previous')
	assert resources.core_page == 0
	assert resources.handle('activity.resources.next')
	assert resources.core_page == 1
	assert !resources.handle('unknown.action')
}
