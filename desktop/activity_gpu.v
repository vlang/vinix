// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct ActivityGpu {
mut:
	available   bool
	devices     u64
	submissions u64
	previous    u64
	last_ms     u64
	initialized bool
	drivers     string
	history     ActivityResourceHistory
}

fn (mut gpu ActivityGpu) sample(mut resources ActivityResources) {
	now := u64(monotonic_millis())
	data := resources.read('/proc/activity_gpu') or {
		gpu.available = false
		gpu.initialized = false
		gpu.history.append(0, now, false)
		return
	}
	gpu.accept_sample(data, now)
}

fn (mut gpu ActivityGpu) accept_sample(data string, now u64) {
	if gpu.initialized && now < gpu.last_ms {
		gpu.history = ActivityResourceHistory{}
		gpu.initialized = false
	}
	mut count := u64(0)
	mut submissions := u64(0)
	mut has_count := false
	mut has_submissions := false
	mut has_drivers := false
	mut start := 0
	for end in 0 .. data.len + 1 {
		if end < data.len && data[end] != `\n` { continue }
		line := unsafe { tos(data.str + start, end - start) }
		if line.starts_with('devices: ') {
			value, parsed := activity_resource_number(line, 9) or { u64(0), -1 }
			count = value
			has_count = parsed == line.len
		} else if line.starts_with('submissions: ') {
			value, parsed := activity_resource_number(line, 13) or { u64(0), -1 }
			submissions = value
			has_submissions = parsed == line.len
		} else if line.starts_with('drivers:') {
			mut offset := 8
			for offset < line.len && line[offset] in [` `, `\t`] { offset++ }
			gpu.drivers = replace_activity_text(gpu.drivers, unsafe { tos(line.str + offset, line.len - offset) }.clone())
			has_drivers = true
		}
		start = end + 1
	}
	if !has_drivers { gpu.drivers = replace_activity_text(gpu.drivers, '') }
	gpu.available = has_count && has_submissions && count > 0
	gpu.devices = count
	gpu.submissions = submissions
	rate := if gpu.initialized && now > gpu.last_ms {
		activity_resource_rate(submissions, gpu.previous, now - gpu.last_ms) or { -1.0 }
	} else {
		-1.0
	}
	gpu.history.append(if rate >= 0 { rate } else { 0 }, now, gpu.available && rate >= 0)
	gpu.previous = submissions
	gpu.last_ms = now
	gpu.initialized = gpu.available
}

fn (gpu &ActivityGpu) build(width int, height int) ui2.Element {
	mut children := frame_elements(12)
	inner := width - 24
	if gpu.available {
		children << activity_resource_label(tr_fill('activity.gpu.drivers', if gpu.drivers != '' {
			gpu.drivers
		} else {
			tr('activity.resources.unavailable')
		}), 12, 12, inner)
		count := gpu.submissions.str()
		children << activity_resource_label(tr_fill('activity.gpu.submissions', count), 12, 43, inner)
		unsafe { count.free() }
		rate := if gpu.history.available() {
			percent_text(gpu.history.latest())
		} else {
			tr('activity.resources.unavailable').clone()
		}
		children << activity_resource_label(tr_fill('activity.gpu.rate', rate), 12, 72, inner)
		unsafe { rate.free() }
		graph_space := height - 200
		graph_height := if graph_space > 160 { 160 } else if graph_space > 0 { graph_space } else { 1 }
		children << activity_resource_graph(&gpu.history, 12, 106, inner, graph_height, 1, app_accent)
	} else {
		children << ui2.Element{
			...ui2.label('', tr('activity.gpu.unavailable'), ui2.rect(12, 12, f64(inner), 42), ui2.TextStyle{ color: body_muted, size: 12 })
			tooltip: tr('activity.gpu.unavailable')
		}
	}
	children << ui2.Element{
		...ui2.label('', tr('activity.gpu.sensors_unavailable'), ui2.rect(12, f64(height - 86), f64(inner), 60), ui2.TextStyle{ color: body_muted, size: 12 })
		tooltip: tr('activity.gpu.sensors_unavailable')
	}
	return ui2.view('activity.gpu.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: app_surface }, children)
}

fn (mut gpu ActivityGpu) free() {
	unsafe { gpu.drivers.free() }
	gpu.drivers = ''
}
