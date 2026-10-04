// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const activity_resource_samples = 60
const activity_resource_cpus = 64

enum ActivityResourceTab {
	cpu
	memory
	disk
	network
}

struct ActivityCpuCounter {
mut:
	total u64
	idle u64
	valid bool
}

struct ActivityCpuSnapshot {
mut:
	all ActivityCpuCounter
	cores [activity_resource_cpus]ActivityCpuCounter
	count int
}

struct ActivityResourceHistory {
mut:
	values [activity_resource_samples]f64
	times [activity_resource_samples]u64
	valid [activity_resource_samples]bool
	count int
	next int
}

fn (mut h ActivityResourceHistory) append(value f64, at_ms u64, valid bool) {
	if h.count > 0 && at_ms < h.times[h.index(h.count - 1)] {
		h.count = 0
		h.next = 0
	}
	h.values[h.next] = value
	h.times[h.next] = at_ms
	h.valid[h.next] = valid
	h.next = (h.next + 1) % activity_resource_samples
	if h.count < activity_resource_samples { h.count++ }
}

fn (h &ActivityResourceHistory) index(position int) int {
	return (h.next + activity_resource_samples - h.count + position) % activity_resource_samples
}

fn (h &ActivityResourceHistory) latest() f64 {
	return if h.count > 0 { h.values[h.index(h.count - 1)] } else { 0.0 }
}

fn (h &ActivityResourceHistory) available() bool {
	return h.count > 0 && h.valid[h.index(h.count - 1)]
}

struct ActivityResources {
mut:
	tab ActivityResourceTab
	previous_cpu ActivityCpuSnapshot
	cpu_history ActivityResourceHistory
	core_history [activity_resource_cpus]ActivityResourceHistory
	memory_history ActivityResourceHistory
	disk_read_history ActivityResourceHistory
	disk_write_history ActivityResourceHistory
	net_recv_history ActivityResourceHistory
	net_send_history ActivityResourceHistory
	cpu_count int
	core_page int
	last_ms u64
	previous_io [4]u64
	io_initialized bool
	io_available bool
	cpu_available bool
	memory_available bool
	memory_total u64
	memory_free u64
	memory_cached u64
	memory_slab u64
	pressure int = -1
	// One buffer for every read, with a borrowed string view while parsing.
	buffer [24576]u8
}

// Parse directly from borrowed procfs bytes: splitting lines or interpolating
// keys would allocate on every refresh of this manually freed application.
fn activity_resource_number(data string, start int) ?(u64, int) {
	mut at := start
	for at < data.len && (data[at] == ` ` || data[at] == `\t`) { at++ }
	begin := at
	mut number := u64(0)
	for at < data.len && data[at] >= `0` && data[at] <= `9` {
		digit := u64(data[at] - `0`)
		if number > (u64(-1) - digit) / 10 { return none }
		number = number * 10 + digit
		at++
	}
	if at == begin { return none }
	if at < data.len && data[at] != ` ` && data[at] != `\t` && data[at] != `\n` && data[at] != `\r` {
		return none
	}
	return number, at
}

fn activity_resource_field(data string, key string) ?u64 {
	mut start := 0
	for start < data.len {
		mut matches := start + key.len < data.len
		for j := 0; matches && j < key.len; j++ { matches = data[start + j] == key[j] }
		if matches && data[start + key.len] == `:` {
			value, _ := activity_resource_number(data, start + key.len + 1) or { return none }
			return value
		}
		for start < data.len && data[start] != `\n` { start++ }
		start++
	}
	return none
}

fn activity_resource_cpu_snapshot(data string) ActivityCpuSnapshot {
	mut snapshot := ActivityCpuSnapshot{}
	mut start := 0
	for start < data.len {
		mut end := start
		for end < data.len && data[end] != `\n` { end++ }
		if end - start >= 5 && data[start] == `c` && data[start + 1] == `p` && data[start + 2] == `u` {
			mut at := start + 3
			mut core := -1
			if data[at] != ` ` && data[at] != `\t` {
				value, next := activity_resource_number(data, at) or { start = end + 1; continue }
				if value >= activity_resource_cpus { start = end + 1; continue }
				core = int(value)
				at = next
			}
			mut fields := [8]u64{}
			mut count := 0
			for count < 8 {
				value, next := activity_resource_number(data, at) or { break }
				if next > end { break }
				fields[count] = value
				count++
				at = next
			}
			if count >= 4 {
				mut total := u64(0)
				mut valid := true
				for n in fields {
					if total > u64(-1) - n { valid = false; break }
					total += n
				}
				if fields[3] > u64(-1) - fields[4] { valid = false }
				counter := ActivityCpuCounter{total: total, idle: fields[3] + fields[4], valid: valid}
				if core == -1 { snapshot.all = counter }
				else {
					snapshot.cores[core] = counter
					if core + 1 > snapshot.count { snapshot.count = core + 1 }
				}
			}
		}
		start = end + 1
	}
	return snapshot
}

// A reset, a wrapped counter, or an unmeasured interval is a gap in history.
// Reporting the unsigned underflow as an enormous spike would be misleading.
fn activity_resource_rate(current u64, previous u64, elapsed_ms u64) ?f64 {
	if elapsed_ms == 0 || current < previous { return none }
	return f64(current - previous) * 1000.0 / f64(elapsed_ms)
}

fn activity_resource_cpu_percent(current ActivityCpuCounter, previous ActivityCpuCounter) ?f64 {
	if !current.valid || !previous.valid || current.total <= previous.total || current.idle < previous.idle {
		return none
	}
	total := current.total - previous.total
	idle := current.idle - previous.idle
	if idle > total { return none }
	return f64(total - idle) * 100.0 / f64(total)
}

fn (mut r ActivityResources) read(path string) ?string {
	fd := desktop_open_ro_nonblock(path)
	if fd < 0 { return none }
	got := desktop_read(fd, &r.buffer[0], u64(r.buffer.len))
	desktop_close(fd)
	if got <= 0 || got >= r.buffer.len { return none }
	return unsafe { tos(&r.buffer[0], int(got)) }
}

fn (mut r ActivityResources) sample(m &ActivityMonitor) {
	now_ms := m.sampled_ns / 1_000_000
	if now_ms == 0 || now_ms == r.last_ms { return }
	if r.last_ms != 0 && now_ms < r.last_ms {
		r.cpu_history = ActivityResourceHistory{}
		r.memory_history = ActivityResourceHistory{}
		r.disk_read_history = ActivityResourceHistory{}
		r.disk_write_history = ActivityResourceHistory{}
		r.net_recv_history = ActivityResourceHistory{}
		r.net_send_history = ActivityResourceHistory{}
		r.core_history = [activity_resource_cpus]ActivityResourceHistory{}
		r.previous_cpu = ActivityCpuSnapshot{}
		r.io_initialized = false
	}
	elapsed := if now_ms > r.last_ms { now_ms - r.last_ms } else { u64(0) }
	if stat_text := r.read('/proc/stat') {
		next := activity_resource_cpu_snapshot(stat_text)
		if percent := activity_resource_cpu_percent(next.all, r.previous_cpu.all) {
			r.cpu_history.append(percent, now_ms, true)
			r.cpu_available = true
		} else { r.cpu_history.append(0, now_ms, false); r.cpu_available = false }
		r.cpu_count = next.count
		for i in 0 .. r.cpu_count {
			if percent := activity_resource_cpu_percent(next.cores[i], r.previous_cpu.cores[i]) {
				r.core_history[i].append(percent, now_ms, true)
			} else { r.core_history[i].append(0, now_ms, false) }
		}
		r.previous_cpu = next
	} else {
		r.previous_cpu = ActivityCpuSnapshot{}
		r.cpu_history.append(0, now_ms, false)
		for i in 0 .. r.cpu_count { r.core_history[i].append(0, now_ms, false) }
		r.cpu_available = false
	}
	r.memory_total = m.total_memory
	r.memory_free = if m.total_memory >= m.used_memory { m.total_memory - m.used_memory } else { u64(0) }
	r.memory_cached = m.cached_memory
	r.pressure = -1
	if meminfo := r.read('/proc/meminfo') {
		r.memory_total = (activity_resource_field(meminfo, 'MemTotal') or { r.memory_total / 1024 }) * 1024
		r.memory_free = (activity_resource_field(meminfo, 'MemFree') or { r.memory_free / 1024 }) * 1024
		r.memory_cached = (activity_resource_field(meminfo, 'Cached') or { r.memory_cached / 1024 }) * 1024
		r.memory_slab = (activity_resource_field(meminfo, 'Slab') or { 0 }) * 1024
		if level := activity_resource_field(meminfo, 'VinixMemoryPressure') {
			if level <= 2 { r.pressure = int(level) }
		}
	}
	r.memory_available = r.memory_total > 0 && r.memory_free <= r.memory_total
	used_percent := if r.memory_available { f64(r.memory_total - r.memory_free) * 100.0 / f64(r.memory_total) } else { 0.0 }
	r.memory_history.append(used_percent, now_ms, r.memory_available)
	mut current_io := [4]u64{}
	mut valid_io := false
	if io_text := r.read('/proc/activity_io') {
		mut found := 0
		for i, key in ['disk_read_bytes', 'disk_write_bytes', 'net_recv_bytes', 'net_send_bytes']! {
			if value := activity_resource_field(io_text, key) { current_io[i] = value; found++ }
		}
		valid_io = found == 4
	}
	mut rates := [4]f64{}
	mut measured := [4]bool{}
	for i in 0 .. 4 {
		if valid_io && r.io_initialized {
			if rate := activity_resource_rate(current_io[i], r.previous_io[i], elapsed) {
				rates[i] = rate
				measured[i] = true
			}
		}
	}
	r.disk_read_history.append(rates[0], now_ms, measured[0])
	r.disk_write_history.append(rates[1], now_ms, measured[1])
	r.net_recv_history.append(rates[2], now_ms, measured[2])
	r.net_send_history.append(rates[3], now_ms, measured[3])
	r.previous_io = current_io
	r.io_initialized = valid_io
	r.io_available = valid_io
	r.last_ms = now_ms
}

fn activity_resource_value(history &ActivityResourceHistory, percent bool) string {
	if !history.available() { return tr('activity.resources.unavailable').clone() }
	if percent {
		value := percent_text(history.latest())
		text := '${value}%'
		unsafe { value.free() }
		return text
	}
	value := human_size(u64(history.latest()))
	text := tr_fill('activity.resources.rate', value)
	unsafe { value.free() }
	return text
}

// Takes owned text; free_tree releases it after this frame is presented.
fn activity_resource_label(text string, x int, y int, width int) ui2.Element {
	return ui2.Element{
		...ui2.label(frame_owned_text_id, text, ui2.rect(f64(x), f64(y), f64(width), 22), ui2.TextStyle{
			color: body_text
			size: 12
		})
		tooltip: text
	}
}

fn activity_resource_graph(history &ActivityResourceHistory, x int, y int, width int, height int, limit f64, color u32) ui2.Element {
	mut marks := frame_elements(activity_resource_samples * 2 + 4)
	mut scale := limit
	for position in 0 .. history.count {
		i := history.index(position)
		if history.valid[i] && history.values[i] > scale { scale = history.values[i] }
	}
	if scale <= 0 { scale = 1 }
	for quarter in 1 .. 4 {
		marks << ui2.view('', ui2.rect(0, f64(quarter * height / 4), f64(width), 1), ui2.BoxStyle{bg: body_rule}, [])
	}
	if history.count > 0 {
		first := history.times[history.index(0)]
		last := history.times[history.index(history.count - 1)]
		span := if last > first { last - first } else { u64(1) }
		mut previous_x := -1
		mut previous_y := 0
		for position in 0 .. history.count {
			i := history.index(position)
			if !history.valid[i] { previous_x = -1; continue }
			px := if history.times[i] >= first { int((history.times[i] - first) * u64(width - 2) / span) } else { 0 }
			py := height - 2 - int(history.values[i] * f64(height - 4) / scale)
			if previous_x >= 0 {
				marks << ui2.view('', ui2.rect(f64(previous_x), f64(previous_y), f64(px - previous_x + 2), 2), ui2.BoxStyle{bg: color}, [])
				top := if py < previous_y { py } else { previous_y }
				length := if py < previous_y { previous_y - py } else { py - previous_y }
				marks << ui2.view('', ui2.rect(f64(px), f64(top), 2, f64(length + 2)), ui2.BoxStyle{bg: color}, [])
			} else { marks << ui2.view('', ui2.rect(f64(px), f64(py), 2, 2), ui2.BoxStyle{bg: color}, []) }
			previous_x = px
			previous_y = py
		}
	}
	return ui2.view('activity.resources.graph', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: body_panel
		border_color: body_rule
		border_left: 1
		border_right: 1
		border_top: 1
		border_bottom: 1
	}, marks)
}

fn activity_resource_size_line(key string, bytes u64, x int, y int, width int) ui2.Element {
	value := human_size(bytes)
	line := tr_fill(key, value)
	unsafe { value.free() }
	return activity_resource_label(line, x, y, width)
}

fn (mut r ActivityResources) build(width int, height int) ui2.Element {
	// Borrowed pool arrays must have room before appending; growing this copy
	// would leave the pool owning the old buffer and leak its replacement.
	mut children := frame_elements(if r.tab == .cpu { 12 + 2 * r.cpu_count } else { 30 })
	pad := 12
	inner := if width > 48 { width - 2 * pad } else { 24 }
	button_width := inner / 4
	for i in 0 .. 4 {
		action := match i { 0 { 'activity.resources.cpu' } 1 { 'activity.resources.memory' } 2 { 'activity.resources.disk' } else { 'activity.resources.network' } }
		children << ui2.button(action, tr(action), ui2.rect(f64(pad + i * button_width), 8, f64(button_width), 25), ui2.BoxStyle{
			bg: if int(r.tab) == i { app_accent } else { body_panel }
			radius: 4
		}, ui2.TextStyle{color: if int(r.tab) == i { app_on_accent } else { body_text }, size: 12})
	}
	top := 44
	graph_space := if r.tab in [.disk, .network] { (height - 171) / 2 } else { height - 190 }
	graph_height := if graph_space > 100 { 100 } else if graph_space > 0 { graph_space } else { 1 }
	match r.tab {
		.cpu {
			children << activity_resource_label(activity_resource_value(&r.cpu_history, true), pad, top, inner)
			children << activity_resource_graph(&r.cpu_history, pad, top + 25, inner, graph_height, 100, app_accent)
			columns := if inner >= 480 { 4 } else { 2 }
			rows := if height > top + graph_height + 85 { (height - top - graph_height - 85) / 65 } else { 1 }
			page_size := if rows * columns > 0 { rows * columns } else { columns }
			pages := if r.cpu_count > 0 { (r.cpu_count + page_size - 1) / page_size } else { 1 }
			if r.core_page >= pages { r.core_page = pages - 1 }
			for cell in 0 .. page_size {
				core := r.core_page * page_size + cell
				if core >= r.cpu_count { break }
				cw := inner / columns
				cx := pad + cell % columns * cw
				cy := top + graph_height + 34 + cell / columns * 65
				number := (core + 1).str()
				value := activity_resource_value(&r.core_history[core], true)
				line := tr_fill2('activity.resources.core', number, value)
				unsafe { number.free(); value.free() }
				children << activity_resource_label(line, cx, cy, cw - 8)
				children << activity_resource_graph(&r.core_history[core], cx, cy + 22, cw - 8, 35, 100, app_accent)
			}
			if pages > 1 {
				children << ui2.button('activity.resources.previous', '<', ui2.rect(f64(width - 76), f64(height - 28), 28, 23), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
				children << ui2.button('activity.resources.next', '>', ui2.rect(f64(width - 42), f64(height - 28), 28, 23), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
			}
		}
		.memory {
			pressure := match r.pressure { 0 { tr('activity.resources.pressure.normal') } 1 { tr('activity.resources.pressure.high') } 2 { tr('activity.resources.pressure.critical') } else { tr('activity.resources.unavailable') } }
			used := activity_resource_value(&r.memory_history, true)
			children << activity_resource_label(tr_fill('activity.resources.used', used), pad, top, inner / 2)
			unsafe { used.free() }
			children << activity_resource_label(tr_fill('activity.resources.pressure', pressure), pad + inner / 2, top, inner / 2)
			children << activity_resource_graph(&r.memory_history, pad, top + 25, inner, graph_height, 100, app_accent)
			base := top + graph_height + 32
			children << activity_resource_size_line('activity.resources.total', r.memory_total, pad, base, inner / 2)
			children << activity_resource_size_line('activity.resources.free', r.memory_free, pad + inner / 2, base, inner / 2)
			children << activity_resource_size_line('activity.resources.cached', r.memory_cached, pad, base + 24, inner / 2)
			children << activity_resource_size_line('activity.resources.slab', r.memory_slab, pad + inner / 2, base + 24, inner / 2)
			children << ui2.Element{
				...ui2.label('', tr('activity.resources.memory.note'), ui2.rect(f64(pad), f64(base + 54), f64(inner), 35), ui2.TextStyle{color: body_muted, size: 11})
				tooltip: tr('activity.resources.memory.note')
			}
		}
		.disk, .network {
			incoming := if r.tab == .disk { &r.disk_read_history } else { &r.net_recv_history }
			outgoing := if r.tab == .disk { &r.disk_write_history } else { &r.net_send_history }
			in_key := if r.tab == .disk { 'activity.resources.read' } else { 'activity.resources.received' }
			out_key := if r.tab == .disk { 'activity.resources.written' } else { 'activity.resources.sent' }
			value_in := activity_resource_value(incoming, false)
			value_out := activity_resource_value(outgoing, false)
			children << activity_resource_label(tr_fill(in_key, value_in), pad, top, inner)
			children << activity_resource_label(tr_fill(out_key, value_out), pad, top + 26 + graph_height + 8, inner)
			unsafe { value_in.free(); value_out.free() }
			children << activity_resource_graph(incoming, pad, top + 25, inner, graph_height, 1, app_accent)
			children << activity_resource_graph(outgoing, pad, top + 59 + graph_height, inner, graph_height, 1, activity_busy)
			if r.io_available {
				first := if r.tab == .disk { r.previous_io[0] } else { r.previous_io[2] }
				second := if r.tab == .disk { r.previous_io[1] } else { r.previous_io[3] }
				first_text := human_size(first)
				second_text := human_size(second)
				children << activity_resource_label(tr_fill2('activity.resources.io_totals', first_text, second_text), pad, height - 60, inner)
				unsafe { first_text.free(); second_text.free() }
			}
			key := if r.tab == .disk { 'activity.resources.disk.note' } else { 'activity.resources.network.note' }
			children << ui2.Element{
				...ui2.label('', tr(key), ui2.rect(f64(pad), f64(height - 36), f64(inner), 32), ui2.TextStyle{color: body_muted, size: 11})
				tooltip: tr(key)
			}
		}
	}
	return ui2.view('activity.resources', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{bg: body_panel}, children)
}

fn (mut r ActivityResources) handle(event_id string) bool {
	match event_id {
		'activity.resources.cpu' { r.tab = .cpu }
		'activity.resources.memory' { r.tab = .memory }
		'activity.resources.disk' { r.tab = .disk }
		'activity.resources.network' { r.tab = .network }
		'activity.resources.previous' { if r.core_page > 0 { r.core_page-- } }
		'activity.resources.next' { r.core_page++ }
		else { return false }
	}
	return true
}

// Histories and the scratch buffer live inline. Per-frame labels are owned by
// the UI tree, so there are no retained allocations to release here.
fn (mut r ActivityResources) free() {}
