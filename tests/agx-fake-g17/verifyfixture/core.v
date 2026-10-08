// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// SPDX-License-Identifier: GPL-2.0-only
// Independent path-specific command and Mesa resource provenance oracle.
@[has_globals]
module verifyfixture

#include <verifier-native-abi.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stderr &C.FILE
struct C.vg17_verifier_fixture {
mut:
	command [0x2240]u8
	descriptor [0x15b0]u8
}
struct C.vinix_fake_g17_expected_write {
mut:
	value u64
	value_mask u64
	selector u32
	template_bits u32
	template_mask u32
	address_alignment u32
	flags u32
	pass u32
	mode u32
}
struct C.vinix_fake_g17_address_range {
mut:
	address u64
	size u64
	access u32
	object_handle u32
}
struct C.vinix_fake_g17_resource_reference {
mut:
	address u64
	size u64
	field u32
	provenance u32
	descriptor_member u32
	descriptor_bytes u32
	access u32
}
struct C.vinix_fake_g17_report {
	observed_writes u32
	expected_writes u32
}
fn C.memset(voidptr, i32, usize) voidptr
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.puts(&char) i32
fn C.vinix_fake_g17_verify(voidptr, usize, voidptr, usize, u64, &C.vinix_fake_g17_expected_write, u32, &C.vinix_fake_g17_address_range, u32, &C.vinix_fake_g17_resource_reference, u32, &C.vinix_fake_g17_report) i32
fn C.vinix_fake_g17_error_string(i32) &char
fn C.vinix_fake_g17_expected_write_size() usize
fn C.vinix_fake_g17_address_range_size() usize
fn C.vinix_fake_g17_resource_reference_size() usize
fn C.vinix_fake_g17_report_size() usize

const template_bits = u32(0xa5a40006)
const gpu_base = u64(0x700000000)
const address_base = u64(0x80000000)

fn check(ok bool, line i32, expression &char) bool {
	if !ok { unsafe { C.fprintf(C.stderr, c'check failed at line %d: %s\n', line, expression) } }
	return ok
}
fn check_error(actual i32, expected i32, line i32) bool {
	if actual != expected {
		unsafe { C.fprintf(C.stderr, c'line %d: expected %s, got %s\n', line, C.vinix_fake_g17_error_string(expected), C.vinix_fake_g17_error_string(actual)) }
		return false
	}
	return true
}
fn write_le16(bytes &u8, value u16) {
	unsafe { bytes[0] = u8(value); bytes[1] = u8(value >> 8) }
}
fn write_le32(bytes &u8, value u32) {
	unsafe {
		bytes[0] = u8(value)
		bytes[1] = u8(value >> 8)
		bytes[2] = u8(value >> 16)
		bytes[3] = u8(value >> 24)
	}
}
fn write_le64(bytes &u8, value u64) {
	unsafe { write_le32(bytes, u32(value)); write_le32(bytes + 4, u32(value >> 32)) }
}
fn stream(fixture &C.vg17_verifier_fixture, pass u32) &u8 {
	return unsafe { &fixture.command[0] + usize(pass) * usize(C.VINIX_FAKE_G17_REGISTER_STRIDE) + usize(C.VINIX_FAKE_G17_STREAM_OFFSET) }
}
fn metadata(fixture &C.vg17_verifier_fixture, pass u32) &u8 {
	return unsafe { &fixture.command[0] + usize(pass) * usize(C.VINIX_FAKE_G17_REGISTER_STRIDE) + usize(C.VINIX_FAKE_G17_METADATA_OFFSET) }
}
fn summary(fixture &C.vg17_verifier_fixture, pass u32) &u8 {
	return unsafe { &fixture.descriptor[0] + usize(C.VINIX_FAKE_G17_SUMMARY_OFFSET) + usize(pass) * usize(C.VINIX_FAKE_G17_SUMMARY_STRIDE) }
}
fn build_fixture(fixture &C.vg17_verifier_fixture, writes &C.vinix_fake_g17_expected_write, counts &u16) {
	unsafe {
		mut index := u32(0)
		C.memset(fixture, 0, sizeof(C.vg17_verifier_fixture))
		for pass in u32(0) .. u32(C.VINIX_FAKE_G17_REGISTER_PASSES) {
			stream_gpu := gpu_base + u64(pass) * u64(C.VINIX_FAKE_G17_REGISTER_STRIDE) + u64(C.VINIX_FAKE_G17_STREAM_OFFSET)
			write_le64(metadata(fixture, pass), stream_gpu)
			write_le16(metadata(fixture, pass) + 8, counts[pass])
			write_le16(metadata(fixture, pass) + 10, u16(u32(counts[pass]) * u32(C.VINIX_FAKE_G17_ENTRY_BYTES)))
			write_le64(summary(fixture, pass), stream_gpu)
			write_le16(summary(fixture, pass) + 8, counts[pass])
			for entry in u16(0) .. counts[pass] {
				write := &writes[index]
				encoded := stream(fixture, pass) + usize(entry) * usize(C.VINIX_FAKE_G17_ENTRY_BYTES)
				*write = C.vinix_fake_g17_expected_write{
					value: u64(0x100000000) + u64(index)
					value_mask: u64(0xffffffffffffffff)
					selector: (index + 1) * 8
					template_bits: template_bits
					template_mask: u32(C.VINIX_FAKE_G17_TEMPLATE_MASK)
					pass: pass
					mode: index & 1
				}
				if index % 31 == 0 {
					write.value = address_base + u64(index) * 0x100
					write.address_alignment = 16
					write.flags = u32(C.VINIX_FAKE_G17_VALUE_IS_ADDRESS)
				}
				write_le32(encoded, template_bits | write.selector | write.mode)
				write_le64(encoded + 4, write.value)
				index++
			}
		}
	}
}
fn verify(fixture &C.vg17_verifier_fixture, writes &C.vinix_fake_g17_expected_write, count u32, ranges &C.vinix_fake_g17_address_range, range_count u32, report &C.vinix_fake_g17_report) i32 {
	return unsafe { C.vinix_fake_g17_verify(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], sizeof(fixture.descriptor), gpu_base, writes, count, ranges, range_count, nil, 0, report) }
}
fn verify_resource(fixture &C.vg17_verifier_fixture, writes &C.vinix_fake_g17_expected_write, ranges &C.vinix_fake_g17_address_range, resource &C.vinix_fake_g17_resource_reference, count u32, report &C.vinix_fake_g17_report) i32 {
	return unsafe { C.vinix_fake_g17_verify(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], sizeof(fixture.descriptor), gpu_base, writes, 4, ranges, 1, resource, count, report) }
}
// All interior views are consumed inside the owning caller's stack frame.
// Carry its address as a scalar past the compiler's conservative fixed-array
// reference promotion; the original buffers and allocation policy stay intact.
fn fixture_address(address usize) &C.vg17_verifier_fixture {
	return unsafe { &C.vg17_verifier_fixture(address) }
}

fn test_exact_trace() i32 {
	unsafe {
		mut fixture := C.vg17_verifier_fixture{}
		mut writes := [4]C.vinix_fake_g17_expected_write{}
		mut ranges := [C.vinix_fake_g17_address_range{address: address_base, size: 0x100000, access: u32(C.VINIX_FAKE_G17_VM_READ | C.VINIX_FAKE_G17_VM_WRITE), object_handle: 7}]!
		mut report := C.vinix_fake_g17_report{}
		counts := [u16(1), u16(1), u16(1), u16(1)]!
		write_count := u32(4)
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_OK, 153) { return 1 }
		if !check(report.observed_writes == write_count, 154, c'report.observed_writes == write_count') { return 1 }
		if !check(report.expected_writes == write_count, 155, c'report.expected_writes == write_count') { return 1 }
		stream(fixture_address(usize(&fixture)), 0)[0] ^= u8(8)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_SELECTOR, 158) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		stream(fixture_address(usize(&fixture)), 0)[0] ^= u8(C.VINIX_FAKE_G17_MODE_FIELD)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_MODE, 162) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		stream(fixture_address(usize(&fixture)), 0)[0] ^= u8(2)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_TEMPLATE_BITS, 166) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		stream(fixture_address(usize(&fixture)), 0)[4] ^= u8(0x80)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_VALUE, 170) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		writes[0].value = address_base + 1
		write_le64(stream(fixture_address(usize(&fixture)), 0) + 4, writes[0].value)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_ADDRESS, 175) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		writes[0].pass = 1
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_PASS_ORDER, 179) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		metadata(fixture_address(usize(&fixture)), 0)[10]++
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_STREAM_COUNTERS, 183) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		summary(fixture_address(usize(&fixture)), 0)[10] = 1
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_DESCRIPTOR_SUMMARY, 187) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		metadata(fixture_address(usize(&fixture)), 0)[0] ^= u8(0x10)
		if !check_error(verify(fixture_address(usize(&fixture)), &writes[0], write_count, &ranges[0], 1, &report), C.VINIX_FAKE_G17_STREAM_ADDRESS, 191) { return 1 }
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		if !check(C.vinix_fake_g17_verify(&fixture.command[0], usize(C.VINIX_FAKE_G17_COMMAND_BYTES) - 1, &fixture.descriptor[0], sizeof(fixture.descriptor), gpu_base, &writes[0], write_count, &ranges[0], 1, nil, 0, &report) == C.VINIX_FAKE_G17_COMMAND_TOO_SMALL, 194, c'vinix_fake_g17_verify(fixture.command, VINIX_FAKE_G17_COMMAND_BYTES - 1, fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, write_count, ranges, 1, NULL, 0, &report) == VINIX_FAKE_G17_COMMAND_TOO_SMALL') { return 1 }
		if !check(C.vinix_fake_g17_verify(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], usize(C.VINIX_FAKE_G17_DESCRIPTOR_BYTES) - 1, gpu_base, &writes[0], write_count, &ranges[0], 1, nil, 0, &report) == C.VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL, 199, c'vinix_fake_g17_verify(fixture.command, sizeof(fixture.command), fixture.descriptor, VINIX_FAKE_G17_DESCRIPTOR_BYTES - 1, GPU_BASE, writes, write_count, ranges, 1, NULL, 0, &report) == VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL') { return 1 }
		if !check(C.vinix_fake_g17_verify(&fixture.command[0], sizeof(fixture.command), &fixture.descriptor[0], sizeof(fixture.descriptor), u64(0xffffffffffffffff) - u64(0x50), &writes[0], write_count, &ranges[0], 1, nil, 0, &report) == C.VINIX_FAKE_G17_STREAM_ADDRESS, 204, c'vinix_fake_g17_verify(fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), UINT64_MAX - 0x50, writes, write_count, ranges, 1, NULL, 0, &report) == VINIX_FAKE_G17_STREAM_ADDRESS') { return 1 }
	}
	return 0
}
fn test_recovered_call_site_scale() i32 {
	unsafe {
		mut fixture := C.vg17_verifier_fixture{}
		writes := &C.vinix_fake_g17_expected_write(C.calloc(314, sizeof(C.vinix_fake_g17_expected_write)))
		mut ranges := [C.vinix_fake_g17_address_range{address: address_base, size: 0x100000, access: u32(C.VINIX_FAKE_G17_VM_READ | C.VINIX_FAKE_G17_VM_WRITE), object_handle: 7}]!
		mut report := C.vinix_fake_g17_report{}
		counts := [u16(79), u16(79), u16(78), u16(78)]!
		if !check(writes != nil, 229, c'writes != NULL') { return 1 }
		build_fixture(fixture_address(usize(&fixture)), writes, &counts[0])
		if !check(verify(fixture_address(usize(&fixture)), writes, 314, &ranges[0], 1, &report) == C.VINIX_FAKE_G17_OK, 231, c'verify(&fixture, writes, recovered_calls, ranges, 1, &report) == VINIX_FAKE_G17_OK') { return 1 }
		if !check(report.observed_writes == 314, 233, c'report.observed_writes == recovered_calls') { return 1 }
		if !check(verify(fixture_address(usize(&fixture)), writes, 313, &ranges[0], 1, &report) == C.VINIX_FAKE_G17_WRITE_COUNT, 237, c'verify(&fixture, writes, recovered_calls - 1, ranges, 1, &report) == VINIX_FAKE_G17_WRITE_COUNT') { return 1 }
		C.free(writes)
	}
	return 0
}
fn test_descriptor_resource_provenance() i32 {
	unsafe {
		mut fixture := C.vg17_verifier_fixture{}
		mut writes := [4]C.vinix_fake_g17_expected_write{}
		mut ranges := [C.vinix_fake_g17_address_range{address: address_base, size: 0x1000, access: u32(C.VINIX_FAKE_G17_VM_READ | C.VINIX_FAKE_G17_VM_WRITE), object_handle: 19}]!
		mut resource := C.vinix_fake_g17_resource_reference{address: address_base + 0x100, size: 0x80, field: u32(C.VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_LOAD), provenance: u32(C.VINIX_FAKE_G17_PROVENANCE_GPU_VA), descriptor_member: u32(C.VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING), access: u32(C.VINIX_FAKE_G17_VM_READ)}
		mut report := C.vinix_fake_g17_report{}
		counts := [u16(1), u16(1), u16(1), u16(1)]!
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_OK, 264, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_OK') { return 1 }
		resource.field = u32(C.VINIX_FAKE_G17_RESOURCE_PARTIAL_STORE_PIPELINE)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_OK, 272, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_OK') { return 1 }
		resource.field = u32(C.VINIX_FAKE_G17_RESOURCE_FIELD_COUNT)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_METADATA, 277, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA') { return 1 }
		resource.field = u32(C.VINIX_FAKE_G17_RESOURCE_DEPTH_BUFFER_LOAD)
		resource.access = u32(C.VINIX_FAKE_G17_VM_WRITE)
		ranges[0].access = u32(C.VINIX_FAKE_G17_VM_READ)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_ADDRESS, 285, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS') { return 1 }
		resource.access = u32(C.VINIX_FAKE_G17_VM_READ)
		ranges[0].access |= u32(C.VINIX_FAKE_G17_VM_WRITE)
		resource.address = address_base + 0xff0
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_ADDRESS, 293, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS') { return 1 }
		resource.address = address_base + 0x100
		resource.descriptor_member = 0x100
		resource.descriptor_bytes = 8
		write_le64(&fixture.descriptor[resource.descriptor_member], resource.address)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_OK, 303, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_OK') { return 1 }
		fixture.descriptor[resource.descriptor_member] ^= u8(1)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_VALUE, 308, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_VALUE') { return 1 }
		resource.descriptor_member = u32(C.VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_METADATA, 314, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA') { return 1 }
		resource.descriptor_bytes = 0
		resource.provenance = u32(C.VINIX_FAKE_G17_PROVENANCE_CONSTANT)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resource, 1, &report) == C.VINIX_FAKE_G17_RESOURCE_METADATA, 320, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, &resource, 1, &report) == VINIX_FAKE_G17_RESOURCE_METADATA') { return 1 }
	}
	return 0
}
fn test_depth_stencil_resource_rejections() i32 {
	unsafe {
		mut fixture := C.vg17_verifier_fixture{}
		mut writes := [4]C.vinix_fake_g17_expected_write{}
		mut ranges := [C.vinix_fake_g17_address_range{address: address_base, size: 0x1000, access: u32(C.VINIX_FAKE_G17_VM_READ), object_handle: 29}]!
		mut resources := [
			C.vinix_fake_g17_resource_reference{address: address_base + 0x200, size: 0x80, field: u32(C.VINIX_FAKE_G17_RESOURCE_DEPTH_META_BUFFER_LOAD), provenance: u32(C.VINIX_FAKE_G17_PROVENANCE_GPU_VA), descriptor_member: u32(C.VINIX_FAKE_G17_DESCRIPTOR_DEPTH_META_BUFFER_LOAD), descriptor_bytes: 8, access: u32(C.VINIX_FAKE_G17_VM_READ)},
			C.vinix_fake_g17_resource_reference{address: address_base + 0x400, size: 0x80, field: u32(C.VINIX_FAKE_G17_RESOURCE_STENCIL_META_BUFFER_STORE), provenance: u32(C.VINIX_FAKE_G17_PROVENANCE_GPU_VA), descriptor_member: u32(C.VINIX_FAKE_G17_DESCRIPTOR_STENCIL_META_BUFFER_STORE), descriptor_bytes: 8, access: u32(C.VINIX_FAKE_G17_VM_WRITE)},
		]!
		mut report := C.vinix_fake_g17_report{}
		counts := [u16(1), u16(1), u16(1), u16(1)]!
		build_fixture(fixture_address(usize(&fixture)), &writes[0], &counts[0])
		write_le64(&fixture.descriptor[resources[0].descriptor_member], resources[0].address)
		write_le64(&fixture.descriptor[resources[1].descriptor_member], resources[1].address)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resources[0], 1, &report) == C.VINIX_FAKE_G17_OK, 365, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, resources, 1, &report) == VINIX_FAKE_G17_OK') { return 1 }
		resources[0].address = address_base + 0x2000
		write_le64(&fixture.descriptor[resources[0].descriptor_member], resources[0].address)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resources[0], 1, &report) == C.VINIX_FAKE_G17_RESOURCE_ADDRESS, 375, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, resources, 1, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS') { return 1 }
		resources[0].address = address_base + 0x200
		write_le64(&fixture.descriptor[resources[0].descriptor_member], resources[0].address)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resources[0], 2, &report) == C.VINIX_FAKE_G17_RESOURCE_ADDRESS, 386, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, resources, 2, &report) == VINIX_FAKE_G17_RESOURCE_ADDRESS') { return 1 }
		ranges[0].access |= u32(C.VINIX_FAKE_G17_VM_WRITE)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resources[0], 2, &report) == C.VINIX_FAKE_G17_OK, 391, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, resources, 2, &report) == VINIX_FAKE_G17_OK') { return 1 }
		fixture.descriptor[resources[1].descriptor_member] ^= u8(1)
		if !check(verify_resource(fixture_address(usize(&fixture)), &writes[0], &ranges[0], &resources[0], 2, &report) == C.VINIX_FAKE_G17_RESOURCE_VALUE, 397, c'vinix_fake_g17_verify( fixture.command, sizeof(fixture.command), fixture.descriptor, sizeof(fixture.descriptor), GPU_BASE, writes, 4, ranges, 1, resources, 2, &report) == VINIX_FAKE_G17_RESOURCE_VALUE') { return 1 }
	}
	return 0
}
@[export: 'main']
pub fn run() i32 {
	if !check(C.vinix_fake_g17_expected_write_size() == sizeof(C.vinix_fake_g17_expected_write), 406, c'vinix_fake_g17_expected_write_size() == sizeof(struct vinix_fake_g17_expected_write)') { return 1 }
	if !check(C.vinix_fake_g17_address_range_size() == sizeof(C.vinix_fake_g17_address_range), 408, c'vinix_fake_g17_address_range_size() == sizeof(struct vinix_fake_g17_address_range)') { return 1 }
	if !check(C.vinix_fake_g17_resource_reference_size() == sizeof(C.vinix_fake_g17_resource_reference), 410, c'vinix_fake_g17_resource_reference_size() == sizeof(struct vinix_fake_g17_resource_reference)') { return 1 }
	if !check(C.vinix_fake_g17_report_size() == sizeof(C.vinix_fake_g17_report), 412, c'vinix_fake_g17_report_size() == sizeof(struct vinix_fake_g17_report)') { return 1 }
	if !check(test_exact_trace() == 0, 414, c'test_exact_trace() == 0') { return 1 }
	if !check(test_recovered_call_site_scale() == 0, 415, c'test_recovered_call_site_scale() == 0') { return 1 }
	if !check(test_descriptor_resource_provenance() == 0, 416, c'test_descriptor_resource_provenance() == 0') { return 1 }
	if !check(test_depth_stencil_resource_rejections() == 0, 417, c'test_depth_stencil_resource_rejections() == 0') { return 1 }
	C.puts(c'fake G17 HAL300 verifier tests passed')
	return 0
}
