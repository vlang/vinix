// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_disk_usage_capacity_read_views_reports_and_refresh_do_not_retain_heap() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := DiskUsageApp{capacity_view: true}
	for language in [DesktopLanguage.en, .es, .ru]! {
		set_desktop_language(language)
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 880, 546))!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		app.scanner.capacity = disk_usage_read_capacity('/')
		for language in [DesktopLanguage.en, .es, .ru]! {
			set_desktop_language(language)
			for size in [ui2.rect(0, 0, 880, 546), ui2.rect(0, 0, 400, 250), ui2.rect(0, 0, 180, 96)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
			}
		}
		data := app.scanner.report_csv()
		unsafe { data.free() }
		app.scanner.capacity = disk_usage_read_capacity('/vinix-capacity-missing')
		assert !app.scanner.capacity.valid
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 250))!)
		missing := app.scanner.report_csv()
		unsafe { missing.free() }
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

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
