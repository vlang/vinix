// SPDX-License-Identifier: GPL-2.0-or-later
module generators

import os

fn test_metadata_rejects_runtime_constructor_work() {
	raw := os.read_file(os.getenv('VINIX_GENERATOR_RAW_METADATA')) or { panic(err) }
	static_metadata(raw) or { panic(err) }
	for damaged in [raw + '\n' + raw, raw.replace('memcpy(', 'runtime_copy('),
		raw.replace('.info_version = 1', '.info_version = runtime_version()'),
		raw.replace('.name, (u8[64])', '.name, (u8[32])')] {
		if result := static_metadata(damaged) {
			assert false, result
		}
	}
}

fn test_macho_rejects_truncated_counts_offsets_and_runtime_sections() {
	data := os.read_bytes(os.getenv('VINIX_GENERATOR_OBJECT')) or { panic(err) }
	descriptor(data) or { panic(err) }
	for length in [0, 4, 31, 32, data.len - 1] {
		if result := descriptor(data[..length]) {
			assert false, result.str()
		}
	}
	for offset in [0, 12, 16, 20, 36] {
		mut damaged := data.clone()
		for index in offset .. offset + 4 { damaged[index] = 0xff }
		if result := descriptor(damaged) {
			assert false, result.str()
		}
	}
}
