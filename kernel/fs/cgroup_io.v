// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import cgcontrol
import lib
import proc

// All tokens are borrowed from the write buffer; none escapes this syscall.
fn cgroup_fields(value string, fields &[8]string) int {
	mut count := 0
	mut offset := 0
	for offset < value.len {
		for offset < value.len && (value[offset] == ` ` || value[offset] == `\t` || value[offset] == `\n`) { offset++ }
		if offset == value.len { break }
		begin := offset
		for offset < value.len && value[offset] != ` ` && value[offset] != `\t` && value[offset] != `\n` { offset++ }
		if count == 8 { return -1 }
		unsafe { fields[count] = tos(value.str + begin, offset - begin) }
		count++
	}
	return count
}

fn parse_io_max(value string, account &proc.CGroupAccount) ?cgcontrol.Device {
	mut fields := [8]string{}
	n := cgroup_fields(value, unsafe { &fields })
	if n < 2 || n > 5 { return none }
	colon := fields[0].index_u8(`:`)
	if colon < 1 || colon == fields[0].len - 1 { return none }
	major := cgcontrol.decimal(unsafe { tos(fields[0].str, colon) })?
	minor := cgcontrol.decimal(unsafe { tos(fields[0].str + colon + 1, fields[0].len - colon - 1) })?
	id := cgcontrol.dev_id(major, minor)?
	sample := cgcontrol.snapshot(proc.cgroup_control(account))
	mut limits := cgcontrol.Device{used: true, id: id}
	for device in sample.io {
		if device.used && device.id == id { limits = device; break }
	}
	mut seen := u32(0)
	for i in 1 .. n {
		token := fields[i]
		equals := token.index_u8(`=`)
		if equals < 1 || equals == token.len - 1 { return none }
		key := unsafe { tos(token.str, equals) }
		amount := unsafe { tos(token.str + equals + 1, token.len - equals - 1) }
		mut rate := u64(0)
		if amount != 'max' { rate = cgcontrol.decimal(amount)?; if rate == 0 { return none } }
		bit := match key { 'rbps' { u32(1) } 'wbps' { u32(2) } 'riops' { u32(4) } 'wiops' { u32(8) } else { return none } }
		if seen & bit != 0 { return none }
		seen |= bit
		match bit { 1 { limits.rbps = rate } 2 { limits.wbps = rate } 4 { limits.riops = rate } else { limits.wiops = rate } }
	}
	return limits
}

fn add_io_limit(mut text lib.Text, label string, value u64) {
	text.add(label)
	if value == 0 { text.add('max') } else { text.add_unsigned(value) }
}

fn cgroup_io_text(account &proc.CGroupAccount, limits bool) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(256) }
	sample := cgcontrol.snapshot(proc.cgroup_control(account))
	for device in sample.io {
		if !device.used { continue }
		if limits && device.rbps == 0 && device.wbps == 0 && device.riops == 0 && device.wiops == 0 { continue }
		text.add_unsigned(cgcontrol.dev_major(device.id)); text.add_byte(`:`)
		text.add_unsigned(cgcontrol.dev_minor(device.id))
		if limits {
			add_io_limit(mut text, ' rbps=', device.rbps)
			add_io_limit(mut text, ' wbps=', device.wbps)
			add_io_limit(mut text, ' riops=', device.riops)
			add_io_limit(mut text, ' wiops=', device.wiops)
		} else {
			text.add(' rbytes='); text.add_unsigned(device.rbytes)
			text.add(' wbytes='); text.add_unsigned(device.wbytes)
			text.add(' rios='); text.add_unsigned(device.rios)
			text.add(' wios='); text.add_unsigned(device.wios)
		}
		text.add_byte(`\n`)
	}
	return text.str()
}

fn cgroup_paged_bytes(group &CGroup) u64 {
	members := cgroup_members(group, true)
	defer { unsafe { members.free() } }
	mut total := u64(0)
	for pid in members {
		anonymous_bytes_of(pid)
		proc.lock_table()
		process := proc.process_at(pid)
		if process != unsafe { nil } { total += process.cgroup_paged_bytes }
		proc.unlock_table()
	}
	return total
}
