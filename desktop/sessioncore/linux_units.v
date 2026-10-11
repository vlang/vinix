// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

// This imports a bounded foreground service into the native session manager.
// Unsupported directives are errors: unit security or lifecycle requirements
// must never be silently discarded during installation.
pub fn import_linux_service(name string, unit string, enabled bool) !Service {
	if !identifier(name) || !name.ends_with('.service') || unit.len == 0
		|| unit.len > 64 * 1024 || unit.contains('\x00') {
		return error('invalid Linux service unit')
	}
	mut service := Service{name: text(name)!, enabled: enabled}
	mut section := ''
	mut seen := u32(0)
	mut start := 0
	for end in 0 .. unit.len + 1 {
		if end < unit.len && unit[end] != `\n` { continue }
		line := unit_trim(unsafe { tos(&unit.str[start], end - start) })
		start = end + 1
		if line.len == 0 || line[0] in [`#`, `;`] { continue }
		if line.ends_with('\\') { return error('unsupported unit line continuation') }
		if line[0] == `[` {
			if line !in ['[Unit]', '[Service]', '[Install]'] {
				return error('unsupported unit section')
			}
			section = line
			continue
		}
		mut equals := -1
		for i, byte in line { if byte == `=` { equals = i; break } }
		if equals < 1 || section == '' { return error('invalid unit assignment') }
		key := unit_trim(unsafe { tos(line.str, equals) })
		value := unit_trim(unsafe { tos(&line.str[equals + 1], line.len - equals - 1) })
		if section == '[Unit]' {
			if key != 'Description' { return error('unsupported Unit directive') }
			continue
		}
		if section == '[Install]' {
			if key != 'WantedBy' || value != 'default.target' {
				return error('unsupported Install directive or target')
			}
			continue
		}
		bit := match key {
			'Type' { u32(1) }
			'ExecStart' { u32(2) }
			'Restart' { u32(4) }
			'RestartSec' { u32(8) }
			'TimeoutStopSec' { u32(16) }
			else { return error('unsupported Service directive') }
		}
		if seen & bit != 0 { return error('duplicate Service directive') }
		seen |= bit
		match key {
			'Type' { if value != 'simple' { return error('unsupported service type') } }
			'ExecStart' {
				words, count := unit_command(value)!
				service.executable = words[0]
				service.argument_count = count - 1
				for i in 1 .. count { service.arguments[i - 1] = words[i] }
			}
			'Restart' {
				service.restart = match value {
					'no' { .never }
					'on-failure' { .on_failure }
					'always' { .always }
					else { return error('unsupported restart policy') }
				}
			}
			'RestartSec' { service.restart_delay_ms = unit_duration(value)! }
			'TimeoutStopSec' { service.stop_timeout_ms = unit_duration(value)! }
			else {}
		}
	}
	if seen & 3 != 3 { return error('Type=simple and ExecStart are required') }
	return service
}

fn unit_trim(value string) string {
	mut start := 0
	mut end := value.len
	for start < end && value[start] in [` `, `\t`, `\r`] { start++ }
	for end > start && value[end - 1] in [` `, `\t`, `\r`] { end-- }
	return unsafe { tos(&value.str[start], end - start) }
}

fn unit_duration(value string) !i64 {
	ms := value.ends_with('ms')
	length := if ms { value.len - 2 } else if value.ends_with('s') { value.len - 1 } else { value.len }
	if length <= 0 { return error('invalid service duration') }
	mut whole := i64(0)
	mut fraction := i64(0)
	mut digits := 0
	mut dot := false
	for i in 0 .. length {
		byte := value[i]
		if byte == `.` && !ms && !dot && i > 0 && i + 1 < length {
			dot = true
			continue
		}
		if byte < `0` || byte > `9` { return error('invalid service duration') }
		if dot {
			digits++
			if digits > 3 { return error('unsupported service duration precision') }
			fraction = fraction * 10 + i64(byte - `0`)
		} else {
			whole = whole * 10 + i64(byte - `0`)
			if whole > 60000 { return error('service duration exceeds native limit') }
		}
	}
	for digits > 0 && digits < 3 { fraction *= 10; digits++ }
	result := if ms { whole } else { whole * 1000 + fraction }
	if result < 100 || result > 60000 { return error('service duration outside native limits') }
	return result
}

fn unit_command(value string) !([17]Text, int) {
	mut words := [17]Text{}
	mut count := 0
	mut word := Text{}
	mut quote := u8(0)
	mut escaped := false
	mut present := false
	mut closed_quote := false
	for byte in value {
		if byte in [`$`, `%`] { return error('unsupported unit expansion') }
		mut next := byte
		if escaped {
			next = match byte {
				`s` { ` ` }
				`t` { `\t` }
				`n` { `\n` }
				`r` { `\r` }
				`\\`, `'`, `"` { byte }
				else { return error('unsupported unit escape') }
			}
			escaped = false
		} else if byte == `\\` {
			if closed_quote { return error('text after quoted unit argument') }
			escaped = true
			present = true
			continue
		} else if quote != 0 {
			if byte == quote { quote = 0; closed_quote = true; continue }
		} else if byte in [` `, `\t`] {
			if present {
				if count == words.len { return error('too many service arguments') }
				words[count] = word
				count++
				word = Text{}
				present = false
				closed_quote = false
			}
			continue
		} else if byte in [`'`, `"`] {
			if present { return error('quote must start a unit argument') }
			quote = byte
			present = true
			continue
		} else if closed_quote || byte == `;` {
			return error('unsupported unit command syntax')
		}
		if word.len == word.bytes.len - 1 { return error('service argument too long') }
		word.bytes[word.len] = next
		word.len++
		present = true
	}
	if escaped || quote != 0 { return error('unfinished unit argument') }
	if present {
		if count == words.len { return error('too many service arguments') }
		words[count] = word
		count++
	}
	if count == 0 || !words[0].str().starts_with('/') {
		return error('service executable must be an absolute path without prefixes')
	}
	return words, count
}
