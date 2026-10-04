// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(index u32) u64

fn test_activity_browsing_releases_repeated_snapshot_and_frame_allocations() {
	mut app := ActivityApp{}
	mut record := ActivitySample{pid: 900001, ppid: 1, threads: 2, memory_bytes: 1_000_000, cpu_time_ns: 1_000_000_000}
	for index, byte in '/bin/worker[900001]' { record.name[index] = byte }
	mut header := ActivityTable{sample_ns: 1_000_000_000, total: 1, total_memory: 256_000_000, free_memory: 128_000_000}
	app.monitor.apply_snapshot(&header, &record, 1)
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 900, 540))!
	free_tree(warm)
	C.vinix_heap_begin()
	for iteration in 0 .. 100 {
		app.monitor.hierarchy = iteration % 2 == 1
		header.sample_ns += 1_000_000_000
		record.cpu_time_ns += 25_000_000
		app.monitor.apply_snapshot(&header, &record, 1)
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 900, 540))!
		free_tree(tree)
	}
	app.close_app()
	live := C.vinix_heap_end()
	if live != 0 {
		for index in u32(0) .. C.vinix_heap_count() { eprintln(C.vinix_heap_size_at(index)) }
	}
	assert live == 0, 'Activity Monitor repeated snapshots kept ${live} bytes'
}

fn test_activity_inspector_releases_cached_line_rebuilds_and_frames() {
	mut inspector := ActivityInspector{pid: 900001, pid_text: '900001'.clone(), width: 900, status_available: true,
		command_available: true, memory_available: true, files_available: true,
		command: '/bin/worker --long-command "two words"'.clone(), status: 'State: S\nUid: 0\nThreads: 2'.clone(),
		maps: '00001000-00002000 rw-p 00000000 00:00 0 [heap]'.clone(), smaps: 'Rss: 4 kB\nPrivate_Dirty: 4 kB'.clone(),
		files: '0: /dev/tty\n1: socket:[123]'.clone()}
	begin_frame_elements()
	warm := inspector.build(900, 540)
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		inspector.rebuild_lines()
		begin_frame_elements()
		tree := inspector.build(900, 540)
		free_tree(tree)
	}
	inspector.close()
	live := C.vinix_heap_end()
	if live != 0 {
		for index in u32(0) .. C.vinix_heap_count() { eprintln(C.vinix_heap_size_at(index)) }
	}
	assert live == 0, 'Inspector repeated line rebuilding kept ${live} bytes'
}

fn test_activity_short_process_view_with_all_columns_keeps_pool_buffer_owned() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	mut records := [32]ActivitySample{}
	for index in 0 .. records.len {
		records[index].pid = 900001 + index
		records[index].ppid = 1
		records[index].threads = 2
		records[index].memory_bytes = 1_000_000
		for offset, byte in '/bin/worker' { records[index].name[offset] = byte }
	}
	header := ActivityTable{sample_ns: 1_000_000_000, total: u32(records.len),
		total_memory: 256_000_000, free_memory: 128_000_000}
	app.monitor.apply_snapshot(&header, &records[0], records.len)
	for columns in [u32(0x0f), u32(0x1ff)]! {
		app.monitor.columns = columns
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 400))!)
		C.vinix_heap_begin()
		for _ in 0 .. 12 {
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 900, 400))!)
		}
		live := C.vinix_heap_end()
		assert live == 0, 'short process view with columns ${columns} retained ${live} bytes'
	}
}
