// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn activity_inspector_io_fixture(base u64) ActivityInspectorIoSnapshot {
	mut snapshot := ActivityInspectorIoSnapshot{}
	for index in 0 .. activity_inspect_io_count {
		snapshot.values[index] = base + u64(index * 100)
		snapshot.valid[index] = true
	}
	return snapshot
}

fn test_activity_inspector_io_parser_reads_six_counters_and_rejects_malformed_values() {
	data := 'rchar: 100\nwchar: 200\nread_bytes: 300\nwrite_bytes: 400\nnet_recv_bytes: 500\nnet_send_bytes: 600\n'
	snapshot := activity_inspector_io_snapshot(data, true)
	for index in 0 .. activity_inspect_io_count {
		assert snapshot.valid[index]
		assert snapshot.values[index] == u64((index + 1) * 100)
	}
	missing := activity_inspector_io_snapshot(data, false)
	for valid in missing.valid { assert !valid }
	broken := activity_inspector_io_snapshot('rchar: 18446744073709551616\nwchar: -1\nread_bytes: 12junk\nwrite_bytes: 12 trailing\nnet_recv_bytes: 0\nnet_send_bytes: 99\r\n', true)
	assert !broken.valid[0] && !broken.valid[1] && !broken.valid[2] && !broken.valid[3]
	assert broken.valid[4] && broken.values[4] == 0
	assert broken.valid[5] && broken.values[5] == 99
}

fn test_activity_inspector_io_rates_use_actual_interval_and_mark_first_sample_unknown() {
	mut io := ActivityInspectorIo{}
	io.apply(42, 1000, activity_inspector_io_fixture(1000))
	for index in 0 .. activity_inspect_io_count {
		assert io.totals.valid[index]
		assert !io.rate_valid[index]
	}
	io.apply(42, 1250, activity_inspector_io_fixture(1500))
	for index in 0 .. activity_inspect_io_count {
		assert io.rate_valid[index] && io.rates[index] == 2000
	}
	io.apply(42, 3250, activity_inspector_io_fixture(1500))
	for index in 0 .. activity_inspect_io_count {
		assert io.rate_valid[index] && io.rates[index] == 0
	}
}

fn test_activity_inspector_io_invalidates_pid_changes_counter_resets_and_missing_samples() {
	mut io := ActivityInspectorIo{}
	io.apply(42, 1000, activity_inspector_io_fixture(1000))
	io.apply(43, 1500, activity_inspector_io_fixture(2000))
	for valid in io.rate_valid { assert !valid }
	io.apply(43, 2000, activity_inspector_io_fixture(500))
	for valid in io.rate_valid { assert !valid }
	io.apply(43, 3000, activity_inspector_io_fixture(750))
	for index in 0 .. activity_inspect_io_count { assert io.rate_valid[index] && io.rates[index] == 250 }
	io.apply(43, 3500, ActivityInspectorIoSnapshot{})
	for index in 0 .. activity_inspect_io_count { assert !io.totals.valid[index] && !io.rate_valid[index] }
	io.apply(43, 4000, activity_inspector_io_fixture(1000))
	for valid in io.rate_valid { assert !valid }
	io.apply(43, 4000, activity_inspector_io_fixture(1100))
	for valid in io.rate_valid { assert !valid }
	io.apply(43, 3900, activity_inspector_io_fixture(1200))
	for valid in io.rate_valid { assert !valid }
}

fn test_activity_inspector_io_partial_fields_recover_independently() {
	mut io := ActivityInspectorIo{}
	first := activity_inspector_io_snapshot('rchar: 100\nwchar: 500\n', true)
	second := activity_inspector_io_snapshot('rchar: 200\nwchar: 300\nnet_recv_bytes: 1000\n', true)
	io.apply(42, 1000, first)
	io.apply(42, 1500, second)
	assert io.rate_valid[0] && io.rates[0] == 200
	assert !io.rate_valid[1] && !io.rate_valid[4]
	assert io.totals.valid[4] && io.totals.values[4] == 1000
	third := activity_inspector_io_snapshot('rchar: 300\nwchar: 500\nnet_recv_bytes: 1500\n', true)
	io.apply(42, 2500, third)
	assert io.rate_valid[1] && io.rates[1] == 200
	assert io.rate_valid[4] && io.rates[4] == 500
}

fn test_activity_inspector_io_tab_has_cached_lines_and_unknown_rates() {
	mut inspector := ActivityInspector{width: 400, io_available: true}
	defer { inspector.close() }
	inspector.io.apply(42, 1000, activity_inspector_io_fixture(1000))
	inspector.rebuild_lines()
	assert inspector.io_lines.len >= activity_inspect_io_count
	unknown_text := inspector.io_lines.join('')
	defer { unsafe { unknown_text.free() } }
	assert unknown_text.contains(tr('activity.inspector.io.unknown'))
	assert inspector.handle(activity_inspect_io)
	assert inspector.tab == .io && inspector.scroll == 0
	assert inspector.line_count() == inspector.io_lines.len
	assert inspector.line_at(0) == inspector.io_lines[0]
	// A matching-size frame uses the existing text storage.
	inspector.language = desktop_language
	before := inspector.io_lines[0].str
	tree := inspector.build(400, 300)
	free_tree(tree)
	assert inspector.io_lines[0].str == before
	inspector.io.apply(42, 2000, activity_inspector_io_fixture(2000))
	inspector.rebuild_lines()
	for line in inspector.io_lines {
		assert !line.contains(tr('activity.inspector.io.unknown'))
	}
}

fn test_activity_inspector_exports_raw_io_totals() {
	mut inspector := ActivityInspector{
		pid: 42
		pid_text: '42'.clone()
		io_available: true
		io_raw: 'rchar: 1234\nwchar: 5678\nread_bytes: 0\nwrite_bytes: 1024\nnet_recv_bytes: 12\nnet_send_bytes: 34\n'.clone()
	}
	defer { inspector.close() }
	home := os.join_path(os.temp_dir(), 'vinix-activity-inspector-io-test')
	path := os.join_path(home, 'Activity-Monitor-42.txt')
	os.mkdir_all(home)!
	defer {
		os.rm(path) or {}
		os.rmdir(home) or {}
		unsafe { home.free() path.free() }
	}
	assert inspector.export_report(home)
	report := os.read_file(path)!
	defer { unsafe { report.free() } }
	assert report.contains('PROCESS I/O (bytes)')
	assert report.contains(inspector.io_raw)
}
