// SPDX-License-Identifier: GPL-2.0-or-later
module releaseasset

import crypto.sha256
import encoding.binary
import os

fn validate(data []u8, expected string) ! {
	if expected.len != 64 || expected.bytes().any(!it.is_hex_digit())
		|| sha256.sum(data).hex() != expected.to_lower() {
		return error('iOS release runtime checksum mismatch')
	}
	if data.len < 64 || data[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1]
		|| binary.little_endian_u16_at(data, 16) != 2
		|| binary.little_endian_u16_at(data, 18) != 183 {
		return error('iOS release runtime must be a static ARM64 ELF executable')
	}
	offset := binary.little_endian_u64_at(data, 32)
	size := u64(binary.little_endian_u16_at(data, 54))
	count := u64(binary.little_endian_u16_at(data, 56))
	if count == 0 || size < 56 || offset > u64(data.len) || size * count > u64(data.len) - offset {
		return error('iOS release runtime has invalid ELF program headers')
	}
	for index in 0 .. count {
		kind := binary.little_endian_u32_at(data, int(offset + index * size))
		if kind in [u32(2), 3] {
			return error('iOS release runtime must not need a dynamic loader')
		}
	}
}

pub fn stage(source string, destination string, expected string) ! {
	data := os.read_bytes(source)!
	defer { unsafe { data.free() } }
	validate(data, expected)!
	os.mkdir_all(os.dir(destination))!
	temporary := destination + '.verified-${os.getpid()}'
	defer { os.rm(temporary) or {} }
	os.write_file_array(temporary, data)!
	os.chmod(temporary, 0o755)!
	os.rename(temporary, destination)!
}
