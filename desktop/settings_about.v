// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct SettingsAbout {
mut:
	kernel string
	cpu string
	memory string
	uptime string
	initialized bool
	buffer [8192]u8
}

fn settings_about_value(data string, field string) string {
	mut start := 0
	for end in 0 .. data.len + 1 {
		if end < data.len && data[end] != `\n` { continue }
		line := unsafe { tos(data.str + start, end - start) }
		if line.starts_with(field) && (field.ends_with(':') || field.len == line.len
			|| line[field.len] == ` ` || line[field.len] == `\t` || line[field.len] == `:`) {
			mut at := field.len
			for at < line.len && (line[at] == ` ` || line[at] == `\t` || line[at] == `:`) { at++ }
			if at < line.len { return unsafe { tos(line.str + at, line.len - at).clone() } }
		}
		start = end + 1
	}
	return ''
}

fn (mut about SettingsAbout) read(path string) string {
	got := desktop_read_file(path, &about.buffer[0], u64(about.buffer.len))
	if got <= 0 { return '' }
	mut length := int(got)
	for length > 0 && (about.buffer[length - 1] == `\n` || about.buffer[length - 1] == `\r`) { length-- }
	return unsafe { tos(&about.buffer[0], length) }
}

fn (mut about SettingsAbout) refresh() {
	about.kernel = replaced_terminal_text(about.kernel, about.read('/proc/version').clone())
	cpu_data := about.read('/proc/cpuinfo')
	mut cpu := settings_about_value(cpu_data, 'model name')
	if cpu.len == 0 { cpu = settings_about_value(cpu_data, 'Hardware') }
	if cpu.len == 0 { cpu = settings_about_value(cpu_data, 'Processor') }
	if cpu.len == 0 {
		architecture := settings_about_value(cpu_data, 'CPU architecture:')
		if architecture.len > 0 { cpu = 'ARMv${architecture}' }
		unsafe { architecture.free() }
	}
	about.cpu = replaced_terminal_text(about.cpu, cpu)
	mem_data := about.read('/proc/meminfo')
	about.memory = replaced_terminal_text(about.memory, settings_about_value(mem_data, 'MemTotal:'))
	uptime_data := about.read('/proc/uptime')
	mut end := 0
	for end < uptime_data.len && uptime_data[end] != ` ` && uptime_data[end] != `\t` { end++ }
	about.uptime = replaced_terminal_text(about.uptime, if end > 0 { unsafe { tos(uptime_data.str, end).clone() } } else { '' })
	about.initialized = true
}

fn (about &SettingsAbout) pane(width int) []ui2.Element {
	mut out := frame_elements(12)
	inner := width - 2 * settings_padding
	out << ui2.label('', tr('settings.category.about'), ui2.rect(16, 16, f64(inner), 28),
		ui2.TextStyle{ color: body_heading, size: 18, bold: true })
	keys := ['settings.about.kernel', 'settings.about.cpu', 'settings.about.memory', 'settings.about.uptime']!
	values := [about.kernel, about.cpu, about.memory, about.uptime]!
	for index, key in keys {
		y := 62 + index * 58
		out << ui2.label('', tr(key), ui2.rect(16, f64(y), f64(inner), 20),
			ui2.TextStyle{ color: body_muted, size: 11, bold: true })
		value := if values[index].len > 0 { values[index] } else { tr('settings.about.unavailable') }
		out << ui2.Element{
			...ui2.label('', value, ui2.rect(16, f64(y + 20), f64(inner), 24),
				ui2.TextStyle{ color: body_text, size: 12 })
			tooltip: value
		}
	}
	out << ui2.button('settings.about.refresh', tr('settings.about.refresh'), ui2.rect(16, 304, 120, 28),
		ui2.BoxStyle{ bg: settings_choice_bg, radius: 5 }, ui2.TextStyle{ color: body_text, size: 12, align: .center })
	return out
}

fn (mut about SettingsAbout) release() {
	unsafe {
		about.kernel.free()
		about.cpu.free()
		about.memory.free()
		about.uptime.free()
	}
	about = SettingsAbout{}
}

fn (mut a SettingsApp) close_app() {
	a.about.release()
}
