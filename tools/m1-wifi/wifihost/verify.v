// SPDX-License-Identifier: GPL-2.0-or-later
module wifihost

pub const required_symbols = ['wifi__initialise', 'wifi__poll', 'wifi__WifiDevice__read',
	'wifi__WifiDevice__write', 'wifi__WifiDevice__ioctl', 'brcm_m1_prepare', 'brcm_m1_status',
	'brcm_m1_upload', 'brcm_m1_boot', 'brcm_m1_join', 'brcm_m1_poll', 'brcm_m1_read', 'brcm_m1_write',
	'brcm_m1_stop', 'bw_probe', 'bw_start', 'bw_poll', 'bw_join_wpa2']

pub fn kernel_file_request_id() []u8 {
	mut bytes := []u8{}
	for word in [u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b, 0xad97e90e83f1ed67, 0x31eb5d1c5ff23b69] {
		for i in 0 .. 8 { bytes << u8(word >> (8 * i)) }
	}
	return bytes
}

fn little(data []u8, offset int, width int) u64 {
	mut result := u64(0)
	for i in 0 .. width { result |= u64(data[offset + i]) << (8 * i) }
	return result
}

fn extent(data []u8, offset u64, size u64) bool {
	return offset <= u64(data.len) && size <= u64(data.len) - offset
}

pub fn elf_symbols(data []u8) !map[string]bool {
	if data.len < 64 || data[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] {
		return error('expected a little-endian ELF64 executable')
	}
	if little(data, 16, 2) != 2 || little(data, 18, 2) != 183 || little(data, 20, 4) != 1 || little(data, 52, 2) != 64 {
		return error('expected a linked AArch64 ET_EXEC kernel')
	}
	entry := little(data, 24, 8)
	phoff := little(data, 32, 8)
	shoff := little(data, 40, 8)
	phsize := little(data, 54, 2)
	phnum := little(data, 56, 2)
	shsize := little(data, 58, 2)
	shnum := little(data, 60, 2)
	if phsize != 56 || phnum == 0 || !extent(data, phoff, phnum * phsize) {
		return error('invalid program-header table')
	}
	if shsize != 64 || shnum == 0 || !extent(data, shoff, shnum * shsize) {
		return error('invalid section-header table')
	}
	mut executable_entry := false
	for i in 0 .. int(phnum) {
		p := int(phoff) + i * 56
		kind := little(data, p, 4)
		if kind in [u64(2), 3] { return error('kernel must not need a dynamic loader') }
		if kind == 1 {
			offset := little(data, p + 8, 8)
			va := little(data, p + 16, 8)
			filesz := little(data, p + 32, 8)
			memsz := little(data, p + 40, 8)
			if filesz > memsz || !extent(data, offset, filesz) {
				return error('invalid PT_LOAD extent')
			}
			if little(data, p + 4, 4) & 1 != 0 && entry >= va && entry - va < memsz {
				executable_entry = true
			}
		}
	}
	if !executable_entry { return error('entry point is outside executable load segments') }
	if data.bytestr().count(kernel_file_request_id().bytestr()) != 1 {
		return error('kernel must contain exactly one Limine kernel-file request')
	}
	mut names := map[string]bool{}
	mut undefined := map[string]bool{}
	for i in 0 .. int(shnum) {
		s := int(shoff) + i * 64
		if little(data, s + 4, 4) != 2 { continue }
		offset := little(data, s + 24, 8)
		size := little(data, s + 32, 8)
		link := little(data, s + 40, 4)
		stride := little(data, s + 56, 8)
		if stride != 24 || size % 24 != 0 || !extent(data, offset, size) || link >= shnum {
			return error('invalid symbol table')
		}
		strings := int(shoff) + int(link) * 64
		pool_offset := little(data, strings + 24, 8)
		pool_size := little(data, strings + 32, 8)
		if little(data, strings + 4, 4) != 3 || !extent(data, pool_offset, pool_size) {
			return error('invalid string table')
		}
		pool := data[int(pool_offset)..int(pool_offset + pool_size)]
		for j in 0 .. int(size / 24) {
			p := int(offset) + j * 24
			name := little(data, p, 4)
			if name >= u64(pool.len) { return error('symbol name out of bounds') }
			tail := pool[int(name)..]
			end := tail.index(u8(0))
			if end < 0 { return error('unterminated symbol name') }
			text := tail[..end]
			if text.any(it > 127) { return error('symbol name is not ASCII') }
			if text.len > 0 {
				if little(data, p + 6, 2) != 0 {
					names[text.bytestr()] = true
				} else {
					undefined[text.bytestr()] = true
				}
			}
		}
	}
	if undefined.len > 0 {
		mut values := undefined.keys()
		values.sort()
		return error('unresolved symbols: ' + values.join(', '))
	}
	mut missing := required_symbols.filter(it !in names)
	if missing.len > 0 {
		missing.sort()
		return error('missing linked Wi-Fi symbols: ' + missing.join(', '))
	}
	return names
}

fn body(source string, name string) !string {
	needle := 'void ' + name + '(void) {\n'
	mut start := 0
	for start < source.len {
		position := start + (source[start..].index(needle) or { break })
		if position == 0 || source[position - 1] == `\n` {
			tail := source[position + needle.len..]
			if tail.starts_with('}') { return '' }
			end := tail.index('\n}') or { break }
			return tail[..end + 1]
		}
		start = position + 1
	}
	return error('missing generated function: ' + name)
}

pub fn verify_hooks(source string) ! {
	init := body(source, 'console__initialise')!
	poll := body(source, 'console__poll_uart_input')!
	if init.count('wifi__initialise();') != 1 {
		return error('missing/duplicate Wi-Fi initialization')
	}
	if poll.count('wifi__poll();') != 1 { return error('missing/duplicate Wi-Fi polling') }
	callback := init.index('sched__set_uart_poll_callback(') or { return error('missing UART poll callback') }
	if (init.index('wifi__initialise();') or { -1 }) >= callback {
		return error('poll callback installed before Wi-Fi initialization')
	}
	if !poll.contains('virtio_input__poll();') || !poll.contains('uart__getc()') {
		return error('existing UART/VirtIO input hooks were lost')
	}
}
