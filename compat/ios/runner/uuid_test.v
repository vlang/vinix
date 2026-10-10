// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn uuid_test_worker(index int) []string {
	mut samples := []string{cap: 1000}
	mut observed := [16]u8{}
	mut missing := [16]u8{init: 0xff}
	for _ in 0 .. 1000 {
		mut output := [32]u8{init: 0xaa}
		darwin_set_errno(i32(177 + index))
		darwin_uuid_generate(unsafe { &output[8] })
		assert unsafe { *C.ios_errno_address() } == 177 + index
		for i in 0 .. 8 { assert output[i] == 0xaa && output[24 + i] == 0xaa }
		assert output[14] & 0xf0 == 0x40 && output[16] & 0xc0 == 0x80
		for i in 0 .. 16 {
			observed[i] |= output[8 + i]
			missing[i] &= output[8 + i]
		}
		samples << output[8..24].hex()
	}
	// Every unreserved bit must vary across this sample, independently of
	// uniqueness. This catches counters and mostly constant UUID generators.
	for i in 0 .. 16 {
		mask := if i == 6 { u8(0x0f) } else if i == 8 { u8(0x3f) } else { u8(0xff) }
		assert observed[i] & mask == mask && missing[i] & mask == 0
	}
	return samples
}

fn test_darwin_uuid() {
	mut seen := map[string]bool{}
	for _ in 0 .. 2 {
		system_data_start()!
		mut workers := []thread []string{}
		for index in 0 .. 8 { workers << spawn uuid_test_worker(index) }
		for samples in workers.wait() {
			for sample in samples {
				assert !seen[sample]
				seen[sample] = true
			}
		}
		system_data_stop()
	}
	assert seen.len == 16000
	assert libsystem_symbol('/usr/lib/libSystem.B.dylib', '_uuid_generate')! != 0
	println('IOS-UUID: 16000 unique version-4 UUIDs, native entropy, all random bits vary, guarded outputs, thread-local errno and two teardowns')
}
