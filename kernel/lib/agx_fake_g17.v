// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module lib

#include "agx_fake_g17.h"

pub struct C.vinix_fake_g17_expected_write {
pub mut:
	value             u64
	value_mask        u64
	selector          u32
	template_bits     u32
	template_mask     u32
	address_alignment u32
	flags             u32
	pass              u32
	mode              u32
}

pub struct C.vinix_fake_g17_address_range {
pub mut:
	address       u64
	size          u64
	access        u32
	object_handle u32
}

pub struct C.vinix_fake_g17_resource_reference {
pub mut:
	address           u64
	size              u64
	field             u32
	provenance        u32
	descriptor_member u32
	descriptor_bytes  u32
	access            u32
	reserved          u32
}

pub struct C.vinix_fake_g17_report {
pub mut:
	observed        u64
	expected        u64
	error           u32
	pass            u32
	entry           u32
	observed_writes u32
	expected_writes u32
}

fn g17_read_le16(bytes &u8) u16 {
	unsafe {
		return u16(bytes[0]) | (u16(bytes[1]) << 8)
	}
}

fn g17_read_le32(bytes &u8) u32 {
	unsafe {
		return u32(bytes[0]) | (u32(bytes[1]) << 8) | (u32(bytes[2]) << 16) | (u32(bytes[3]) << 24)
	}
}

fn g17_read_le64(bytes &u8) u64 {
	unsafe {
		return u64(g17_read_le32(bytes)) | (u64(g17_read_le32(bytes + 4)) << 32)
	}
}

fn g17_fail(report &C.vinix_fake_g17_report, error_code i32, pass u32, entry u32, observed u64, expected u64) i32 {
	unsafe {
		report.error = u32(error_code)
		report.pass = pass
		report.entry = entry
		report.observed = observed
		report.expected = expected
	}
	return error_code
}

fn g17_address_allowed(address u64, alignment u32, ranges &C.vinix_fake_g17_address_range, count u32) bool {
	if alignment == 0 || alignment & (alignment - 1) != 0 || address & u64(alignment - 1) != 0 {
		return false
	}
	unsafe {
		for i := u32(0); i < count; i++ {
			if ranges[i].size != 0 && address >= ranges[i].address && address - ranges[i].address < ranges[i].size {
				return true
			}
		}
	}
	return false
}

fn g17_range_allowed(address u64, size u64, access u32, ranges &C.vinix_fake_g17_address_range, count u32) bool {
	mask := u32(C.VINIX_FAKE_G17_VM_READ) | u32(C.VINIX_FAKE_G17_VM_WRITE)
	if address == 0 || size == 0 || address > u64(-1) - size || access == 0 || access & ~mask != 0 {
		return false
	}
	unsafe {
		for i := u32(0); i < count; i++ {
			range := &ranges[i]
			if range.size != 0 && range.object_handle != 0 && range.access != 0 && range.access & ~mask == 0
				&& address >= range.address && address - range.address <= range.size
				&& size <= range.size - (address - range.address) && range.access & access == access {
				return true
			}
		}
	}
	return false
}

@[export: 'vinix_fake_g17_expected_write_size']
fn fake_g17_expected_write_size() usize { return sizeof(C.vinix_fake_g17_expected_write) }

@[export: 'vinix_fake_g17_address_range_size']
fn fake_g17_address_range_size() usize { return sizeof(C.vinix_fake_g17_address_range) }

@[export: 'vinix_fake_g17_resource_reference_size']
fn fake_g17_resource_reference_size() usize { return sizeof(C.vinix_fake_g17_resource_reference) }

@[export: 'vinix_fake_g17_report_size']
fn fake_g17_report_size() usize { return sizeof(C.vinix_fake_g17_report) }

@[export: 'vinix_fake_g17_verify']
fn fake_g17_verify(command_pointer voidptr, command_bytes usize, descriptor_pointer voidptr, descriptor_bytes usize,
	command_gpu_address u64, writes &C.vinix_fake_g17_expected_write, write_count u32,
	ranges &C.vinix_fake_g17_address_range, range_count u32,
	resources &C.vinix_fake_g17_resource_reference, resource_count u32, report &C.vinix_fake_g17_report) i32 {
	unsafe {
		command := &u8(command_pointer)
		descriptor := &u8(descriptor_pointer)
		if usize(report) == 0 { return C.VINIX_FAKE_G17_INVALID_ARGUMENT }
		*report = C.vinix_fake_g17_report{ expected_writes: write_count }
		if usize(command) == 0 || usize(descriptor) == 0 || command_gpu_address == 0
			|| (write_count != 0 && usize(writes) == 0) || (range_count != 0 && usize(ranges) == 0)
			|| (resource_count != 0 && usize(resources) == 0) {
			return g17_fail(report, C.VINIX_FAKE_G17_INVALID_ARGUMENT, 0, 0, 0, 0)
		}
		if command_bytes < usize(C.VINIX_FAKE_G17_COMMAND_BYTES) {
			return g17_fail(report, C.VINIX_FAKE_G17_COMMAND_TOO_SMALL, 0, 0, u64(command_bytes), C.VINIX_FAKE_G17_COMMAND_BYTES)
		}
		if descriptor_bytes < usize(C.VINIX_FAKE_G17_DESCRIPTOR_BYTES) {
			return g17_fail(report, C.VINIX_FAKE_G17_DESCRIPTOR_TOO_SMALL, 0, 0, u64(descriptor_bytes), C.VINIX_FAKE_G17_DESCRIPTOR_BYTES)
		}
		for pass := u32(0); pass < resource_count; pass++ {
			item := &resources[pass]
			pending := item.descriptor_member == u32(C.VINIX_FAKE_G17_DESCRIPTOR_MEMBER_PENDING)
			bad_member := if pending {
				item.descriptor_bytes != 0
			} else {
				item.descriptor_bytes != 8 || usize(item.descriptor_member) > descriptor_bytes
					|| usize(item.descriptor_bytes) > descriptor_bytes - usize(item.descriptor_member)
			}
			if item.reserved != 0 || item.field >= u32(C.VINIX_FAKE_G17_RESOURCE_FIELD_COUNT)
				|| (item.provenance != u32(C.VINIX_FAKE_G17_PROVENANCE_BO_RESOURCE) && item.provenance != u32(C.VINIX_FAKE_G17_PROVENANCE_GPU_VA))
				|| bad_member {
				return g17_fail(report, C.VINIX_FAKE_G17_RESOURCE_METADATA, 0, pass, item.field, item.provenance)
			}
			if !g17_range_allowed(item.address, item.size, item.access, ranges, range_count) {
				return g17_fail(report, C.VINIX_FAKE_G17_RESOURCE_ADDRESS, 0, pass, item.address, item.size)
			}
			if !pending && g17_read_le64(descriptor + item.descriptor_member) != item.address {
				return g17_fail(report, C.VINIX_FAKE_G17_RESOURCE_VALUE, 0, pass, g17_read_le64(descriptor + item.descriptor_member), item.address)
			}
		}
		mut observed := u32(0)
		for pass := u32(0); pass < u32(C.VINIX_FAKE_G17_REGISTER_PASSES); pass++ {
			stream_offset := usize(pass) * usize(C.VINIX_FAKE_G17_REGISTER_STRIDE) + usize(C.VINIX_FAKE_G17_STREAM_OFFSET)
			metadata_offset := usize(pass) * usize(C.VINIX_FAKE_G17_REGISTER_STRIDE) + usize(C.VINIX_FAKE_G17_METADATA_OFFSET)
			summary_offset := usize(C.VINIX_FAKE_G17_SUMMARY_OFFSET) + usize(pass) * usize(C.VINIX_FAKE_G17_SUMMARY_STRIDE)
			metadata := command + metadata_offset
			summary := descriptor + summary_offset
			stream_gpu := g17_read_le64(metadata)
			entry_count := g17_read_le16(metadata + 8)
			byte_length := g17_read_le16(metadata + 10)
			if command_gpu_address > u64(-1) - u64(stream_offset) {
				return g17_fail(report, C.VINIX_FAKE_G17_STREAM_ADDRESS, pass, 0, stream_gpu, 0)
			}
			expected_gpu := command_gpu_address + u64(stream_offset)
			if stream_gpu != expected_gpu {
				return g17_fail(report, C.VINIX_FAKE_G17_STREAM_ADDRESS, pass, 0, stream_gpu, expected_gpu)
			}
			if u32(byte_length) > u32(C.VINIX_FAKE_G17_STREAM_BYTES) || u32(byte_length) % u32(C.VINIX_FAKE_G17_ENTRY_BYTES) != 0
				|| u32(entry_count) != u32(byte_length) / u32(C.VINIX_FAKE_G17_ENTRY_BYTES) {
				return g17_fail(report, C.VINIX_FAKE_G17_STREAM_COUNTERS, pass, 0, (u64(entry_count) << 32) | u64(byte_length), u64(byte_length) / u64(C.VINIX_FAKE_G17_ENTRY_BYTES))
			}
			if g17_read_le64(summary) != stream_gpu || g17_read_le16(summary + 8) != entry_count
				|| summary[10] != 0 || summary[11] != 0 || summary[12] != 0 || summary[13] != 0 || summary[14] != 0 || summary[15] != 0 {
				return g17_fail(report, C.VINIX_FAKE_G17_DESCRIPTOR_SUMMARY, pass, 0, g17_read_le64(summary), stream_gpu)
			}
			if u64(observed) + u64(entry_count) > u64(write_count) {
				return g17_fail(report, C.VINIX_FAKE_G17_WRITE_COUNT, pass, 0, u64(observed) + u64(entry_count), write_count)
			}
			for entry := u32(0); entry < u32(entry_count); entry++ {
				golden := &writes[observed]
				encoded := command + stream_offset + usize(entry) * usize(C.VINIX_FAKE_G17_ENTRY_BYTES)
				word := g17_read_le32(encoded)
				selector := word & u32(C.VINIX_FAKE_G17_SELECTOR_FIELD)
				mode := word & u32(C.VINIX_FAKE_G17_MODE_FIELD)
				value := g17_read_le64(encoded + 4)
				report.observed_writes = observed + 1
				if golden.pass != pass {
					return g17_fail(report, C.VINIX_FAKE_G17_PASS_ORDER, pass, entry, pass, golden.pass)
				}
				if golden.selector & ~u32(C.VINIX_FAKE_G17_SELECTOR_FIELD) != 0 {
					return g17_fail(report, C.VINIX_FAKE_G17_INVALID_ARGUMENT, pass, entry, golden.selector, C.VINIX_FAKE_G17_SELECTOR_FIELD)
				}
				if selector != golden.selector {
					return g17_fail(report, C.VINIX_FAKE_G17_SELECTOR, pass, entry, selector, golden.selector)
				}
				if golden.mode > 1 {
					return g17_fail(report, C.VINIX_FAKE_G17_INVALID_ARGUMENT, pass, entry, golden.mode, 1)
				}
				if mode != golden.mode {
					return g17_fail(report, C.VINIX_FAKE_G17_MODE, pass, entry, mode, golden.mode)
				}
				if golden.template_mask & ~u32(C.VINIX_FAKE_G17_TEMPLATE_MASK) != 0 {
					return g17_fail(report, C.VINIX_FAKE_G17_INVALID_ARGUMENT, pass, entry, golden.template_mask, C.VINIX_FAKE_G17_TEMPLATE_MASK)
				}
				if word & golden.template_mask != golden.template_bits & golden.template_mask {
					return g17_fail(report, C.VINIX_FAKE_G17_TEMPLATE_BITS, pass, entry, word & golden.template_mask, golden.template_bits & golden.template_mask)
				}
				if golden.value_mask != 0 && value & golden.value_mask != golden.value & golden.value_mask {
					return g17_fail(report, C.VINIX_FAKE_G17_VALUE, pass, entry, value & golden.value_mask, golden.value & golden.value_mask)
				}
				if golden.flags & u32(C.VINIX_FAKE_G17_VALUE_IS_ADDRESS) != 0 && !g17_address_allowed(value, golden.address_alignment, ranges, range_count) {
					return g17_fail(report, C.VINIX_FAKE_G17_ADDRESS, pass, entry, value, golden.address_alignment)
				}
				if golden.flags & ~u32(C.VINIX_FAKE_G17_VALUE_IS_ADDRESS) != 0 {
					return g17_fail(report, C.VINIX_FAKE_G17_INVALID_ARGUMENT, pass, entry, golden.flags, C.VINIX_FAKE_G17_VALUE_IS_ADDRESS)
				}
				observed++
			}
		}
		report.observed_writes = observed
		if observed != write_count {
			return g17_fail(report, C.VINIX_FAKE_G17_WRITE_COUNT, C.VINIX_FAKE_G17_REGISTER_PASSES, 0, observed, write_count)
		}
		report.error = u32(C.VINIX_FAKE_G17_OK)
		return C.VINIX_FAKE_G17_OK
	}
}

@[export: 'vinix_fake_g17_error_string']
fn fake_g17_error_string(error_code i32) &char {
	return match error_code {
		0 { c'ok' }
		1 { c'invalid verifier request' }
		2 { c'3D command buffer is too small' }
		3 { c'3D descriptor is too small' }
		4 { c'register stream GPU address mismatch' }
		5 { c'register stream counters are invalid' }
		6 { c'descriptor summary mismatch' }
		7 { c'register write count mismatch' }
		8 { c'register pass/order mismatch' }
		9 { c'register selector mismatch' }
		10 { c'register mode mismatch' }
		11 { c'register template bits mismatch' }
		12 { c'register value mismatch' }
		13 { c'GPU address is outside the allowed ranges' }
		14 { c'descriptor resource metadata is invalid' }
		15 { c'descriptor resource is outside its permitted VM binding' }
		16 { c'descriptor resource value does not match its Mesa GPU VA' }
		17 { c'fake G17 work queue is full' }
		else { c'unknown fake-G17 verifier error' }
	}
}
