// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_activity_csv_repeated_exports_release_every_formatting_allocation() {
	monitor := ActivityMonitor{
		rows: [ActivityRow{pid: 42, ppid: 1, threads: 3, uid: 1000, uid_known: true,
			cpu_percent: 12.5, cpu_time_ns: 999, memory_bytes: 4096, name: 'csv', executable: '/bin/csv'}]
		visible: [ActivityVisible{index: 0}]
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		report := monitor.process_csv()
		unsafe { report.free() }
	}
	assert C.vinix_heap_end() == 0
}

fn test_about_release_clears_owned_values_and_can_run_twice() {
	C.vinix_heap_begin()
	mut about := SettingsAbout{kernel: 'kernel'.clone(), cpu: 'cpu'.clone(),
		memory: 'memory'.clone(), uptime: 'uptime'.clone(), initialized: true}
	about.release()
	about.release()
	assert !about.initialized && about.kernel == ''
	assert C.vinix_heap_end() == 0
}

fn test_terminal_search_releases_blank_and_populated_row_text() {
	mut app := TerminalApp{search_open: true}
	app.set_geometry(24, 80)
	app.ingest_output('one populated row'.bytes())
	app.search_input('absent')
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !app.find_output(1)
	}
	assert C.vinix_heap_end() == 0
	app.close_app()
}
