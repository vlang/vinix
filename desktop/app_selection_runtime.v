// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import encoding.binary

// Image publishers can include the static, native runner here instead of
// preinstalling it. No Apple frameworks or emulator are downloaded by setup.
const first_run_ios_payload = '/usr/share/vinix/optional/ios-runtime/run-ios'

fn first_run_ios_payload_available() bool {
	$if arm64 {
		return C.access(&char(first_run_ios_payload.str), C.X_OK) == 0
	} $else {
		return false
	}
}

fn first_run_ios_elf(data []u8) bool {
	if data.len < 64 || data[0] != 0x7f || data[1] != `E` || data[2] != `L`
		|| data[3] != `F` || data[4] != 2 || data[5] != 1 || data[6] != 1
		|| binary.little_endian_u16_at(data, 16) != 2
		|| binary.little_endian_u16_at(data, 18) != 183
		|| binary.little_endian_u32_at(data, 20) != 1
		|| binary.little_endian_u16_at(data, 52) != 64
		|| binary.little_endian_u16_at(data, 54) != 56 {
		return false
	}
	offset := binary.little_endian_u64_at(data, 32)
	count := binary.little_endian_u16_at(data, 56)
	if offset < 64 || offset > u64(data.len) || count == 0 || count > 4096
		|| u64(count) > (u64(data.len) - offset) / 56 {
		return false
	}
	entry := binary.little_endian_u64_at(data, 24)
	mut executable := false
	for i in 0 .. int(count) {
		at := int(offset) + i * 56
		kind := binary.little_endian_u32_at(data, at)
		if kind == 3 { return false } // PT_INTERP: optional runtime must be static.
		if kind != 1 { continue }
		file_offset := binary.little_endian_u64_at(data, at + 8)
		address := binary.little_endian_u64_at(data, at + 16)
		file_size := binary.little_endian_u64_at(data, at + 32)
		if file_offset > u64(data.len) || file_size > u64(data.len) - file_offset { return false }
		if binary.little_endian_u32_at(data, at + 4) & 1 != 0 && entry >= address
			&& entry - address < file_size {
			executable = true
		}
	}
	return executable
}

fn first_run_install_ios_runtime(root string) ! {
	$if !arm64 {
		return error('the native iOS runtime requires ARM64 hardware')
	}
	source := '${root}${first_run_ios_payload}'
	data := os.read_bytes(source)!
	defer { unsafe { data.free() } }
	if !first_run_ios_elf(data) {
		return error('the image contains an invalid static ARM64 iOS runtime')
	}
	directory := '${root}/usr/bin'
	os.mkdir_all(directory)!
	// Publish only a complete executable. Source stays on the image for retry.
	temporary := '${directory}/.run-ios-setup'
	defer { os.rm(temporary) or {} }
	os.write_file_array(temporary, data)!
	os.chmod(temporary, 0o755)!
	os.mv(temporary, '${directory}/run-ios')!
	manifest_directory := '${root}/var/lib/vinix-pkg'
	os.mkdir_all(manifest_directory)!
	os.write_file('${manifest_directory}/ios-runtime.files', 'usr/bin/run-ios\n')!
	$if vinix {
		C.sync()
	}
}
