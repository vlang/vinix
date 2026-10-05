// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <stdio.h>

const activity_action_export_list = 'activity.export.list'
const activity_action_clear_history = 'activity.history.clear'

// Always quote text fields, including embedded quotes and newlines. Numeric
// counters use their original units so the report can be compared in a sheet.
fn activity_csv_text(mut bytes []u8, value string) {
	bytes << u8(`"`)
	for byte in value {
		bytes << byte
		if byte == `"` { bytes << byte }
	}
	bytes << u8(`"`)
}

fn activity_csv_number(mut bytes []u8, value string) {
	for byte in value { bytes << byte }
	bytes << u8(`,`)
	unsafe { value.free() }
}

fn activity_csv_percent(mut bytes []u8, value f64) {
	mut buffer := [96]u8{}
	unsafe {
		length := C.snprintf(&char(&buffer[0]), 96, c'%.17g', value)
		if length > 0 && length < buffer.len {
			for index in 0 .. length { bytes << buffer[index] }
		}
	}
	bytes << u8(`,`)
}

fn (m &ActivityMonitor) process_csv() string {
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	header := 'pid,ppid,threads,uid,cpu_percent,cpu_time_ns,memory_bytes,name,executable\n'
	for byte in header { bytes << byte }
	for visible in m.visible {
		row := &m.rows[visible.index]
		activity_csv_number(mut bytes, row.pid.str())
		activity_csv_number(mut bytes, row.ppid.str())
		activity_csv_number(mut bytes, row.threads.str())
		if row.uid_known { activity_csv_number(mut bytes, row.uid.str()) } else { bytes << u8(`,`) }
		activity_csv_percent(mut bytes, row.cpu_percent)
		activity_csv_number(mut bytes, row.cpu_time_ns.str())
		activity_csv_number(mut bytes, row.memory_bytes.str())
		activity_csv_text(mut bytes, activity_display_name(row.name))
		bytes << u8(`,`)
		activity_csv_text(mut bytes, row.executable)
		bytes << u8(`\n`)
	}
	result := bytes.bytestr()
	unsafe { bytes.free() }
	return result
}

fn (mut a ActivityApp) export_processes(home string) bool {
	filename := 'Activity-Monitor-Processes.csv'
	report := a.monitor.process_csv()
	ok := activity_write_record(home, filename, report)
	unsafe { report.free() }
	if ok {
		path := '${home}/${filename}'
		a.utility_status = replace_activity_text(a.utility_status, tr_fill('activity.list.exported', path))
		unsafe { path.free() }
	} else {
		a.utility_status = replace_activity_text(a.utility_status, tr('activity.inspector.export_failed').clone())
	}
	return ok
}

// Keep the counter baselines: clearing a graph must not create a CPU or I/O
// spike on the next reading. Fixed histories own no heap allocations.
fn (mut a ActivityApp) clear_histories() {
	a.resources.cpu_history = ActivityResourceHistory{}
	a.resources.core_history = [activity_resource_cpus]ActivityResourceHistory{}
	a.resources.memory_history = ActivityResourceHistory{}
	a.resources.disk_read_history = ActivityResourceHistory{}
	a.resources.disk_write_history = ActivityResourceHistory{}
	a.resources.net_recv_history = ActivityResourceHistory{}
	a.resources.net_send_history = ActivityResourceHistory{}
	a.gpu.history = ActivityResourceHistory{}
	a.energy.power_history = ActivityResourceHistory{}
	a.utility_status = replace_activity_text(a.utility_status, tr('activity.history.cleared').clone())
}

fn (mut a ActivityApp) handle_utility(action string) bool {
	match action {
		activity_action_export_list {
			a.export_processes(if desktop_user_home != '' { desktop_user_home } else { desktop_home })
		}
		activity_action_clear_history { a.clear_histories() }
		else { return false }
	}
	return true
}
