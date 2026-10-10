// SPDX-License-Identifier: GPL-2.0-or-later
module wifihost

fn rejected(data []u8, message string) ! {
	elf_symbols(data) or {
		if message != '' && !err.msg().contains(message) {
			return error('Expected ${message}: ${err}')
		}
		return
	}
	return error('Invalid kernel was accepted: ' + message)
}

fn rejected_hooks(text string, message string) ! {
	verify_hooks(text) or {
		if !err.msg().contains(message) { return error('Expected ${message}: ${err}') }
		return
	}
	return error('Invalid hooks were accepted: ' + message)
}

fn changed(data []u8, offset int, width int, value u64) []u8 {
	mut result := data.clone()
	for i in 0 .. width { result[offset + i] = u8(value >> (8 * i)) }
	return result
}

// The original eleven test groups operate on the actual artifact and bad copies.
pub fn verify_regressions(data []u8, source string) ! {
	elf_symbols(data)!
	verify_hooks(source)!
	for length in [0, 63, data.len / 2] { rejected(data[..length], '')! }
	rejected(changed(data, 18, 2, 62), '')!
	rejected(changed(data, 16, 2, 1), '')!
	mut no_symbols := data.clone()
	shoff := int(little(data, 40, 8))
	for i in 0 .. int(little(data, 60, 2)) {
		if little(data, shoff + i * 64 + 4, 4) == 2 {
			no_symbols = changed(no_symbols, shoff + i * 64 + 4, 4, 0)
		}
	}
	rejected(no_symbols, 'missing linked Wi-Fi symbols')!
	mut duplicate := data.clone()
	duplicate << kernel_file_request_id()
	rejected(duplicate, 'exactly one Limine kernel-file request')!
	rejected(changed(data, int(little(data, 32, 8)), 4, 3), '')!
	rejected(changed(data, 24, 8, 0), '')!
	rejected_hooks(source.replace('wifi__initialise();', ''), 'initialization')!
	rejected_hooks(source.replace('wifi__poll();', ''), 'polling')!
	rejected_hooks(source.replace('wifi__poll();', 'wifi__poll(); wifi__poll();'), 'polling')!
}
