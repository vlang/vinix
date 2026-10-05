// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn test_activity_exports_visible_rows_with_lossless_csv_fields() {
	mut monitor := ActivityMonitor{
		rows: [ActivityRow{pid: 42, ppid: 1, threads: 3, uid: 1000, uid_known: true,
			cpu_percent: 12.5, cpu_time_ns: 999, memory_bytes: 4096,
			name: 'a,"b\nc', executable: '/bin/a'}, ActivityRow{pid: 43, name: 'excluded'}]
		visible: [ActivityVisible{index: 0}]
	}
	report := monitor.process_csv()
	defer { unsafe { report.free() } }
	assert report.starts_with('pid,ppid,threads,uid,cpu_percent,cpu_time_ns,memory_bytes,name,executable\n')
	assert report.contains('42,1,3,1000,12.5,999,4096,"a,""b\nc","/bin/a"\n')
	assert !report.contains('excluded')
}

fn test_activity_filters_keep_unknown_owners_out_of_owner_filters() {
	mut monitor := ActivityMonitor{ viewer_uid: 1000, selected_pid: 42 }
	known := ActivityRow{pid: 42, uid: 1000, uid_known: true, cpu_percent: 0}
	other := ActivityRow{pid: 43, uid: 0, uid_known: true, cpu_percent: 2}
	unknown := ActivityRow{pid: 44, uid_known: false}
	monitor.filter = .inactive
	assert monitor.matches_row(&known)
	assert !monitor.matches_row(&other)
	monitor.filter = .other_users
	assert !monitor.matches_row(&known)
	assert monitor.matches_row(&other)
	assert !monitor.matches_row(&unknown)
	monitor.filter = .selected
	assert monitor.matches_row(&known)
	assert !monitor.matches_row(&other)
	monitor.selected_pid = 0
	assert !monitor.matches_row(&known)
}

fn test_selected_process_filter_updates_immediately_with_paused_tree_selection() {
	mut app := ActivityApp{
		monitor: ActivityMonitor{
			rows: [ActivityRow{pid: 1, name: 'root'},
				ActivityRow{pid: 40, ppid: 1, name: 'parent'},
				ActivityRow{pid: 42, ppid: 40, name: 'child'}]
			selected_pid: 42
			filter: .selected
			hierarchy: true
			paused: true
		}
	}
	app.monitor.rebuild_visible()
	assert app.monitor.visible.len == 3
	app.handle('activity.select.40')!
	assert app.monitor.selected_pid == 40
	assert app.monitor.visible.len == 2
	report := app.monitor.process_csv()
	assert !report.contains('"child"')
	unsafe { report.free() }
	app.monitor.selected_pid = 42
	app.monitor.rebuild_visible()
	app.key_input('\x1b[A')
	assert app.monitor.selected_pid == 40
	assert app.monitor.visible.len == 2
}

fn test_clear_activity_graphs_preserves_counter_baselines() {
	mut app := ActivityApp{}
	app.resources.cpu_history.append(50, 1000, true)
	app.resources.core_history[0].append(10, 1000, true)
	app.resources.memory_history.append(20, 1000, true)
	app.resources.disk_read_history.append(99, 1000, true)
	app.gpu.history.append(8, 1000, true)
	app.energy.power_history.append(9, 1000, true)
	app.resources.previous_io = [u64(100), 200, 300, 400]!
	app.resources.io_initialized = true
	app.resources.last_ms = 1000
	app.resources.previous_cpu.all = ActivityCpuCounter{total: 1000, idle: 500, valid: true}
	app.clear_histories()
	assert app.resources.cpu_history.count == 0
	assert app.resources.core_history[0].count == 0
	assert app.resources.memory_history.count == 0
	assert app.resources.disk_read_history.count == 0
	assert app.gpu.history.count == 0
	assert app.energy.power_history.count == 0
	assert app.resources.io_initialized
	assert app.resources.previous_io[0] == 100
	assert app.resources.previous_cpu.all.total == 1000
	assert app.resources.last_ms == 1000
	unsafe { app.utility_status.free() }
}

fn test_activity_export_publishes_report_and_reports_failure() {
	home := os.join_path(os.temp_dir(), 'vinix-parity-${os.getpid()}')
	os.mkdir_all(home)!
	defer { os.rmdir_all(home) or {} }
	mut app := ActivityApp{}
	assert app.export_processes(home)
	assert os.read_file(os.join_path(home, 'Activity-Monitor-Processes.csv'))!.starts_with('pid,ppid,threads,uid,')
	assert !app.export_processes('${home}/missing')
	unsafe { app.utility_status.free() }
}

fn test_terminal_find_wraps_and_searches_utf8_without_cursor_text() {
	mut app := TerminalApp{}
	app.set_geometry(2, 20)
	app.ingest_output('first café\r\nsecond\r\nlast café'.bytes())
	app.search_open = true
	app.search_input('café')
	assert app.search_match == 0
	assert app.scroll == 1
	assert app.find_output(1)
	assert app.search_match == 2
	assert app.scroll == 0
	assert app.find_output(1)
	assert app.search_match == 0
	assert app.find_output(-1)
	assert app.search_match == 2
	app.search_input('\x7f')
	assert editor_bytes_text(app.search_query) == 'caf'
	app.search_input('\x1b')
	assert !app.search_open
	app.search_open = true
	app.search_query.clear()
	app.paste_input('café\n\x1b\t\x7f')
	assert app.search_open
	assert editor_bytes_text(app.search_query) == 'café'
}

fn test_terminal_clear_scrollback_preserves_live_and_alternate_screen() {
	mut app := TerminalApp{}
	app.set_geometry(2, 12)
	app.ingest_output('one\r\ntwo\r\nthree'.bytes())
	assert app.lines.len == 1
	app.clear_scrollback()
	assert app.lines.len == 0
	assert app.row_string(0) == 'two'
	assert app.row_string(1) == 'three'
	app.enter_alternate_screen()
	app.ingest_output('vim'.bytes())
	app.clear_scrollback()
	assert app.row_string(0) == 'vim'
	app.leave_alternate_screen()
	assert app.row_string(1) == 'three'
}

fn test_terminal_search_consumes_escape_keys_and_preserves_whole_utf8_at_limit() {
	mut app := TerminalApp{search_open: true}
	app.set_geometry(2, 12)
	app.search_input('needle')
	app.search_input('\x1b[D\x1b[3~')
	assert editor_bytes_text(app.search_query) == 'needle'
	app.search_input('\x1b[')
	app.search_input('A')
	assert editor_bytes_text(app.search_query) == 'needle'
	app.search_query.clear()
	app.search_input('x'.repeat(terminal_search_limit - 1))
	app.search_input('é')
	assert app.search_query.len == terminal_search_limit - 1
	app.paste_input('é')
	assert app.search_query.len == terminal_search_limit - 1
	app.search_query.clear()
	app.search_input('\xd0')
	assert app.search_query.len == 0
	app.search_input('\xb9')
	assert editor_bytes_text(app.search_query) == 'й'
	app.close_app()
	app.close_app()
}

fn test_about_parser_uses_whole_fields_and_handles_missing_proc_data() {
	assert settings_about_value('processor: 0\nmodel name\t: Vinix CPU\n', 'model name') == 'Vinix CPU'
	assert settings_about_value('MemTotal: 1024 kB\nMemFree: 500 kB\n', 'MemTotal:') == '1024 kB'
	assert settings_about_value('MemFree: 500 kB\n', 'MemTotal:') == ''
	assert settings_about_value('model namesake: wrong\nmodel name: correct\n', 'model name') == 'correct'
	mut app := SettingsApp{category: .about, about: SettingsAbout{initialized: true}}
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 410))!
	free_tree(tree)
	assert app.category == .about
}
