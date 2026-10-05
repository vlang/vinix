// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct ActivityEnergyStats {
mut:
	voltage_mv u64
	current_ma i64
	power_mw i64
	has_voltage bool
	has_current bool
	has_power bool
}

struct ActivityEnergy {
mut:
	stats ActivityEnergyStats
	power_history ActivityResourceHistory
	battery_history BatteryHistory
	battery_percent int = battery_unavailable
	last_ms u64
	buffer [512]u8
}

fn activity_energy_signed_field(data string, key string) ?i64 {
	mut start := 0
	for start < data.len {
		mut matches := start + key.len < data.len
		for j := 0; matches && j < key.len; j++ { matches = data[start + j] == key[j] }
		if matches && data[start + key.len] == `:` {
			mut at := start + key.len + 1
			for at < data.len && (data[at] == ` ` || data[at] == `\t`) { at++ }
			negative := at < data.len && data[at] == `-`
			if at < data.len && (data[at] == `-` || data[at] == `+`) { at++ }
			value, _ := activity_resource_number(data, at) or { return none }
			maximum := u64(0x7fff_ffff_ffff_ffff)
			if value > maximum + if negative { u64(1) } else { u64(0) } { return none }
			if negative {
				if value == maximum + 1 { return i64(-9223372036854775807) - 1 }
				return -i64(value)
			}
			return i64(value)
		}
		for start < data.len && data[start] != `\n` { start++ }
		start++
	}
	return none
}

fn activity_energy_parse(data string) ActivityEnergyStats {
	mut stats := ActivityEnergyStats{}
	if voltage := activity_resource_field(data, 'voltage_mv') {
		stats.voltage_mv = voltage
		stats.has_voltage = true
	}
	if current := activity_energy_signed_field(data, 'current_ma') {
		stats.current_ma = current
		stats.has_current = true
	}
	if power := activity_energy_signed_field(data, 'power_mw') {
		stats.power_mw = power
		stats.has_power = true
	}
	return stats
}

fn (mut energy ActivityEnergy) sample(m &ActivityMonitor) {
	now_ms := m.sampled_ns / 1_000_000
	if now_ms == 0 || now_ms == energy.last_ms { return }
	if energy.last_ms > now_ms { energy.power_history = ActivityResourceHistory{} }
	energy.stats = ActivityEnergyStats{}
	fd := desktop_open_ro_nonblock('/dev/battery-power')
	if fd >= 0 {
		got := desktop_read(fd, &energy.buffer[0], u64(energy.buffer.len))
		desktop_close(fd)
		if got > 0 && got < energy.buffer.len {
			energy.stats = activity_energy_parse(unsafe { tos(&energy.buffer[0], int(got)) })
		}
	}
	energy.power_history.append(f64(energy.stats.power_mw) / 1000.0, now_ms, energy.stats.has_power)
	energy.battery_percent = battery_get(false)
	energy.battery_history = battery_history_snapshot()
	energy.last_ms = now_ms
}

// Fixed-point readings retain their device precision and use the desktop's
// decimal separator. Naming the temporary strings makes their ownership clear.
fn activity_energy_milli_text(value i64) string {
	negative := value < 0
	unsigned := if negative { u64(-(value + 1)) + 1 } else { u64(value) }
	whole := (unsigned / 1000).str()
	fraction := (unsigned % 1000).str()
	padded := if unsigned % 1000 < 10 { '00${fraction}' } else if unsigned % 1000 < 100 { '0${fraction}' } else { fraction.clone() }
	decimal := tr_fill2('activity.cpu.decimal', whole, padded)
	result := if negative { '-${decimal}' } else { decimal.clone() }
	unsafe { whole.free(); fraction.free(); padded.free(); decimal.free() }
	return result
}

fn activity_energy_stat_line(key string, value i64, available bool, x int, y int, width int) ui2.Element {
	text := if available { activity_energy_milli_text(value) } else { tr('activity.resources.unavailable').clone() }
	line := tr_fill(key, text)
	unsafe { text.free() }
	return activity_resource_label(line, x, y, width)
}

fn activity_energy_power_graph(history &ActivityResourceHistory, x int, y int, width int, height int) ui2.Element {
	mut marks := frame_elements(activity_resource_samples * 2 + 2)
	center := height / 2
	marks << ui2.view('', ui2.rect(0, f64(center), f64(width), 1), ui2.BoxStyle{bg: body_rule}, [])
	mut scale := 1.0
	for position in 0 .. history.count {
		i := history.index(position)
		value := if history.values[i] < 0 { -history.values[i] } else { history.values[i] }
		if history.valid[i] && value > scale { scale = value }
	}
	if history.count > 0 {
		first := history.times[history.index(0)]
		last := history.times[history.index(history.count - 1)]
		span := if last > first { last - first } else { u64(1) }
		mut previous_x := -1
		mut previous_y := center
		for position in 0 .. history.count {
			i := history.index(position)
			if !history.valid[i] { previous_x = -1; continue }
			px := if history.times[i] >= first { int((history.times[i] - first) * u64(width - 2) / span) } else { 0 }
			py := center - int(history.values[i] * f64(center - 3) / scale)
			if previous_x >= 0 {
				marks << ui2.view('', ui2.rect(f64(previous_x), f64(previous_y), f64(px - previous_x + 2), 2), ui2.BoxStyle{bg: app_accent}, [])
				top := if py < previous_y { py } else { previous_y }
				length := if py < previous_y { previous_y - py } else { py - previous_y }
				marks << ui2.view('', ui2.rect(f64(px), f64(top), 2, f64(length + 2)), ui2.BoxStyle{bg: app_accent}, [])
			} else { marks << ui2.view('', ui2.rect(f64(px), f64(py), 2, 2), ui2.BoxStyle{bg: app_accent}, []) }
			previous_x = px
			previous_y = py
		}
	}
	return ui2.view('activity.energy.power_graph', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{bg: body_panel}, marks)
}

fn (mut energy ActivityEnergy) build(width int, height int) ui2.Element {
	mut children := frame_elements(12)
	pad := 12
	inner := if width > 48 { width - 2 * pad } else { 24 }
	// Reserve both notes, both value rows and the gap between the graphs.
	graph_space := (height - 173) / 2
	graph_height := if graph_space > 80 { 80 } else if graph_space > 0 { graph_space } else { 1 }
	children << activity_energy_stat_line('activity.energy.voltage', i64(energy.stats.voltage_mv), energy.stats.has_voltage, pad, 8, inner / 2)
	children << activity_energy_stat_line('activity.energy.current', energy.stats.current_ma, energy.stats.has_current, pad + inner / 2, 8, inner / 2)
	children << activity_energy_stat_line('activity.energy.power', energy.stats.power_mw, energy.stats.has_power, pad, 34, inner)
	children << activity_energy_power_graph(&energy.power_history, pad, 62, inner, graph_height)
	children << ui2.Element{
		...ui2.label('', tr('activity.energy.sign_note'), ui2.rect(f64(pad), f64(66 + graph_height), f64(inner), 32), ui2.TextStyle{color: body_muted, size: 11})
		tooltip: tr('activity.energy.sign_note')
	}
	charge := battery_percentage_text(energy.battery_percent)
	children << activity_resource_label(tr_fill('activity.energy.battery', charge), pad, 103 + graph_height, inner)
	children << battery_graph(&energy.battery_history, pad, 129 + graph_height, inner, graph_height)
	children << ui2.Element{
		...ui2.label('', tr('activity.energy.application_note'), ui2.rect(f64(pad), f64(height - 36), f64(inner), 32), ui2.TextStyle{color: body_muted, size: 11})
		tooltip: tr('activity.energy.application_note')
	}
	return ui2.view('activity.energy', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{bg: body_panel}, children)
}

fn (mut energy ActivityEnergy) free() {}
