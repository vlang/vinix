// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// SPDX-License-Identifier: GPL-2.0-only
// Independent recovered-ABI golden encoder oracle, preserving original hashes.
@[has_globals]
module encodefixture

#include <encoder-native-abi.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stderr &C.FILE
struct C.vinix_fake_g17_encoder_inputs {
mut:
	values [4][2]u64
	column_count u32
}
struct C.vinix_fake_g17_expected_write {
	value u64
	value_mask u64
	selector u32
	template_bits u32
	template_mask u32
}
struct C.vinix_fake_g17_report {
	observed_writes u32
}
struct C.vg17_encoder_fixture {
mut:
	command [0x2240]u8
	descriptor [0x15b0]u8
	writes [404]C.vinix_fake_g17_expected_write
	inputs C.vinix_fake_g17_encoder_inputs
}
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.puts(&char) i32
fn C.vinix_fake_g17_encode_3d(voidptr, usize, voidptr, usize, u64, &C.vinix_fake_g17_encoder_inputs, &C.vinix_fake_g17_expected_write, u32, &u32) i32
fn C.vinix_fake_g17_verify(voidptr, usize, voidptr, usize, u64, &C.vinix_fake_g17_expected_write, u32, voidptr, u32, voidptr, u32, &C.vinix_fake_g17_report) i32
fn C.vinix_fake_g17_encoder_inputs_size() usize

const template_bits = u32(0xa5a40006)
const gpu_base = u64(0x700000000)
const reference_hashes = [u64(0xe08e26d9c86b26ed), u64(0x7d25ff57c1c923ad),
	u64(0x6633cda4130e23e8), u64(0xc198dcc7895e8fc8), u64(0xeb5655cae0f9d928),
	u64(0x3731746069103020), u64(0x303eb538faa8b93d), u64(0x4f1b28b6f878f645),
	u64(0x46dbfa35a5032104), u64(0xf57977e9a29b44dc), u64(0x478ffd50361f34e1),
	u64(0x22d03028aba24919), u64(0x93e4f531e719adb9), u64(0x4a2d8b744d4d7ad9),
	u64(0xb5a8d810346c9054), u64(0x49877fccbb777724)]!

fn check(ok bool, line i32, expression &char) bool {
	if !ok { unsafe { C.fprintf(C.stderr, c'check failed at line %d: %s\n', line, expression) } }
	return ok
}

fn write_le32(bytes &u8, value u32) {
	unsafe {
		bytes[0] = u8(value)
		bytes[1] = u8(value >> 8)
		bytes[2] = u8(value >> 16)
		bytes[3] = u8(value >> 24)
	}
}

fn fnv1a(bytes &u8, size usize, initial u64) u64 {
	mut hash := initial
	unsafe {
		for index in usize(0) .. size {
			hash ^= bytes[index]
			hash *= u64(0x100000001b3)
		}
	}
	return hash
}

fn initialize_fixture(fixture &C.vg17_encoder_fixture) {
	unsafe {
		C.memset(fixture, 0, sizeof(C.vg17_encoder_fixture))
		for pass in u32(0) .. u32(C.VINIX_FAKE_G17_REGISTER_PASSES) {
			stream := &fixture.command[0] + usize(pass) * usize(C.VINIX_FAKE_G17_REGISTER_STRIDE) + usize(C.VINIX_FAKE_G17_STREAM_OFFSET)
			for entry := u32(0); usize(entry + 1) * usize(C.VINIX_FAKE_G17_ENTRY_BYTES) <= usize(C.VINIX_FAKE_G17_STREAM_BYTES); entry++ {
				write_le32(stream + usize(entry) * usize(C.VINIX_FAKE_G17_ENTRY_BYTES), template_bits)
			}
			for entry in u32(0) .. u32(C.VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT) {
				fixture.inputs.values[pass][entry] = u64(0xdead000000000000) | (u64(pass) << 16) | u64(entry)
			}
		}
	}
}

fn encoded(fixture &C.vg17_encoder_fixture, capacity u32, count &u32) i32 {
	return unsafe { C.vinix_fake_g17_encode_3d(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], sizeof(fixture.descriptor), gpu_base, &fixture.inputs, &fixture.writes[0], capacity, count) }
}

fn verified(fixture &C.vg17_encoder_fixture, count u32, report &C.vinix_fake_g17_report) i32 {
	return unsafe { C.vinix_fake_g17_verify(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], sizeof(fixture.descriptor), gpu_base, &fixture.writes[0], count, nil, 0, nil, 0, report) }
}

fn fixture_hash(fixture &C.vg17_encoder_fixture) u64 {
	return unsafe { fnv1a(&fixture.descriptor[0], sizeof(fixture.descriptor), fnv1a(&fixture.command[0], sizeof(fixture.command), u64(0xcbf29ce484222325))) }
}

fn run_branch_matrix() i32 {
	unsafe {
		for bit_800 in u32(0) .. u32(2) {
			for bit_418 in u32(0) .. u32(2) {
				for bit_b48 in u32(0) .. u32(2) {
					for wide in u32(0) .. u32(2) {
						mut fixture := C.vg17_encoder_fixture{}
						mut report := C.vinix_fake_g17_report{}
						expected_per_pass := u32(92) + 2 * bit_800 + 2 * bit_b48
						expected_writes := u32(4) * expected_per_pass
						branch_key := (bit_800 << 3) | (bit_418 << 2) | (bit_b48 << 1) | wide
						mut external_writes := u32(0)
						mut write_count := u32(0xffffffff)
						initialize_fixture(&fixture)
						fixture.descriptor[0x800] = u8(bit_800)
						fixture.descriptor[0x418] = u8(bit_418)
						fixture.descriptor[0xb48] = u8(bit_b48)
						fixture.inputs.column_count = if wide != 0 { u32(8) } else { u32(4) }
						result := encoded(&fixture, u32(C.VINIX_FAKE_G17_MAX_WRITES), &write_count)
						if !check(result == C.VINIX_FAKE_G17_ENCODE_OK, 130, c'result == VINIX_FAKE_G17_ENCODE_OK') { return 1 }
						if !check(write_count == expected_writes, 131, c'write_count == expected_writes') { return 1 }
						if !check(fixture_hash(&fixture) == reference_hashes[branch_key], 132, c'fnv1a( fixture.descriptor, sizeof(fixture.descriptor), fnv1a(fixture.command, sizeof(fixture.command), UINT64_C(0xcbf29ce484222325))) == reference_hashes[branch_key]') { return 1 }
						for index in u32(0) .. write_count {
							write := &fixture.writes[index]
							if !check(write.template_bits == template_bits, 141, c'write->template_bits == TEMPLATE_BITS') { return 1 }
							if !check(write.template_mask == C.VINIX_FAKE_G17_TEMPLATE_MASK, 142, c'write->template_mask == VINIX_FAKE_G17_TEMPLATE_MASK') { return 1 }
							if !check(write.value_mask == u64(0xffffffffffffffff), 144, c'write->value_mask == UINT64_MAX') { return 1 }
							if (write.value & u64(0xffff000000000000)) == u64(0xdead000000000000) { external_writes++ }
						}
						if !check(external_writes == C.VINIX_FAKE_G17_REGISTER_PASSES * C.VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT, 149, c'external_writes == VINIX_FAKE_G17_REGISTER_PASSES * VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT') { return 1 }
						if !check(verified(&fixture, write_count, &report) == C.VINIX_FAKE_G17_OK, 152, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count, NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_OK') { return 1 }
						if !check(report.observed_writes == write_count, 158, c'report.observed_writes == write_count') { return 1 }
					}
				}
			}
		}
	}
	return 0
}

fn run_failure_checks() i32 {
	unsafe {
		mut fixture := C.vg17_encoder_fixture{}
		mut report := C.vinix_fake_g17_report{}
		mut write_count := u32(0xffffffff)
		initialize_fixture(&fixture)
		if !check(encoded(&fixture, u32(C.VINIX_FAKE_G17_MAX_WRITES) - 1, &write_count) == C.VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY, 174, c'vinix_fake_g17_encode_3d( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs, fixture.writes, VINIX_FAKE_G17_MAX_WRITES - 1, &write_count) == VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY') { return 1 }
		if !check(write_count == 0, 179, c'write_count == 0') { return 1 }
		initialize_fixture(&fixture)
		if !check(encoded(&fixture, u32(C.VINIX_FAKE_G17_MAX_WRITES), &write_count) == C.VINIX_FAKE_G17_ENCODE_OK, 182, c'vinix_fake_g17_encode_3d( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs, fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) == VINIX_FAKE_G17_ENCODE_OK') { return 1 }
		fixture.command[C.VINIX_FAKE_G17_STREAM_OFFSET] ^= u8(2)
		if !check(verified(&fixture, write_count, &report) == C.VINIX_FAKE_G17_TEMPLATE_BITS, 188, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count, NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_TEMPLATE_BITS') { return 1 }
		fixture.command[C.VINIX_FAKE_G17_STREAM_OFFSET] ^= u8(2)
		fixture.command[C.VINIX_FAKE_G17_STREAM_OFFSET + 4] ^= u8(1)
		if !check(verified(&fixture, write_count, &report) == C.VINIX_FAKE_G17_VALUE, 195, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count, NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_VALUE') { return 1 }
	}
	return 0
}

fn run_dense_reference() i32 {
	unsafe {
		mut fixture := C.vg17_encoder_fixture{}
		mut report := C.vinix_fake_g17_report{}
		mut write_count := u32(0)
		C.memset(&fixture, 1, sizeof(C.vg17_encoder_fixture))
		C.memset(&fixture.inputs, 0, sizeof(C.vinix_fake_g17_encoder_inputs))
		fixture.inputs.column_count = 8
		for pass in u32(0) .. u32(C.VINIX_FAKE_G17_REGISTER_PASSES) {
			for event in u32(0) .. u32(C.VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT) {
				fixture.inputs.values[pass][event] = u64(0xcafe000000000000) | (u64(pass) << 16) | u64(event)
			}
		}
		if !check(encoded(&fixture, u32(C.VINIX_FAKE_G17_MAX_WRITES), &write_count) == C.VINIX_FAKE_G17_ENCODE_OK, 221, c'vinix_fake_g17_encode_3d( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs, fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) == VINIX_FAKE_G17_ENCODE_OK') { return 1 }
		if !check(write_count == 388, 226, c'write_count == 388') { return 1 }
		if !check(fixture_hash(&fixture) == u64(0xfa742deac45458bd), 230, c'hash == UINT64_C(0xfa742deac45458bd)') { return 1 }
		if !check(verified(&fixture, write_count, &report) == C.VINIX_FAKE_G17_OK, 231, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count, NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_OK') { return 1 }
	}
	return 0
}

fn run_append_reference() i32 {
	unsafe {
		mut fixture := C.vg17_encoder_fixture{}
		mut report := C.vinix_fake_g17_report{}
		mut write_count := u32(0)
		mut appended := u32(0)
		address := u64(0x0000123456789abc)
		initialize_fixture(&fixture)
		fixture.inputs.column_count = 4
		C.memcpy(&fixture.descriptor[0x7f8], &address, sizeof(u64))
		if !check(encoded(&fixture, u32(C.VINIX_FAKE_G17_MAX_WRITES), &write_count) == C.VINIX_FAKE_G17_ENCODE_OK, 252, c'vinix_fake_g17_encode_3d( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, &fixture.inputs, fixture.writes, VINIX_FAKE_G17_MAX_WRITES, &write_count) == VINIX_FAKE_G17_ENCODE_OK') { return 1 }
		if !check(write_count == 372, 257, c'write_count == 372') { return 1 }
		if !check(fixture_hash(&fixture) == u64(0x628f4651b79099f7), 258, c'fnv1a(fixture.descriptor, sizeof(fixture.descriptor), fnv1a(fixture.command, sizeof(fixture.command), UINT64_C(0xcbf29ce484222325))) == UINT64_C(0x628f4651b79099f7)') { return 1 }
		for index in u32(0) .. write_count {
			if fixture.writes[index].selector == u32(0xa0e0) {
				if !check(fixture.writes[index].value == u64(0x123456789000), 264, c'fixture.writes[index].value == UINT64_C(0x123456789000)') { return 1 }
				appended++
			}
		}
		if !check(appended == C.VINIX_FAKE_G17_REGISTER_PASSES, 268, c'appended == VINIX_FAKE_G17_REGISTER_PASSES') { return 1 }
		if !check(verified(&fixture, write_count, &report) == C.VINIX_FAKE_G17_OK, 269, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, fixture.writes, write_count, NULL, 0, NULL, 0, &report) == VINIX_FAKE_G17_OK') { return 1 }
	}
	return 0
}

@[export: 'main']
pub fn run() i32 {
	if !check(C.vinix_fake_g17_encoder_inputs_size() == sizeof(C.vinix_fake_g17_encoder_inputs), 278, c'vinix_fake_g17_encoder_inputs_size() == sizeof(struct vinix_fake_g17_encoder_inputs)') { return 1 }
	if !check(C.VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT == 2, 280, c'VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT == 2') { return 1 }
	if !check(C.VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT == 0, 281, c'VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT == 0') { return 1 }
	if !check(C.VINIX_FAKE_G17_MAX_WRITES == 404, 282, c'VINIX_FAKE_G17_MAX_WRITES == 404') { return 1 }
	if !check(run_branch_matrix() == 0, 283, c'run_branch_matrix() == 0') { return 1 }
	if !check(run_dense_reference() == 0, 284, c'run_dense_reference() == 0') { return 1 }
	if !check(run_append_reference() == 0, 285, c'run_append_reference() == 0') { return 1 }
	if !check(run_failure_checks() == 0, 286, c'run_failure_checks() == 0') { return 1 }
	C.puts(c'fake G17 recovered 3D encoder tests passed')
	return 0
}
