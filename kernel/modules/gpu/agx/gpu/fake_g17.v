// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module gpu

// Fake G17 execution stops at the firmware boundary: it verifies the encoded
// HAL300 3D register streams, then generates a host-side completion through the
// same WorkQueue/DmaFence path used by a real backend.  It deliberately does
// not emulate PMP, RTKit, UAT or G17 firmware acceptance.

import drm.syncobj
import gpu.agx.workqueue

#include "agx_fake_g17.h"
#include "agx_fake_g17_encode.h"

fn C.vinix_fake_g17_expected_write_size() u64
fn C.vinix_fake_g17_address_range_size() u64
fn C.vinix_fake_g17_report_size() u64
fn C.vinix_fake_g17_encoder_inputs_size() u64
fn C.vinix_fake_g17_verify(command voidptr, command_bytes u64,
	descriptor voidptr, descriptor_bytes u64, command_gpu_address u64,
	writes voidptr, write_count u32, ranges voidptr, range_count u32,
	report voidptr) int
fn C.vinix_fake_g17_encode_3d(command voidptr, command_bytes u64,
	descriptor voidptr, descriptor_bytes u64, command_gpu_address u64,
	inputs voidptr, writes voidptr, write_capacity u32, write_count &u32) int

pub const fake_g17_ok = u32(0)
pub const fake_g17_invalid_argument = u32(1)
pub const fake_g17_queue_full = u32(14)
pub const fake_g17_value_is_address = u32(1) << 0
pub const fake_g17_external_event_count = 5
pub const fake_g17_external_decision_count = 1
pub const fake_g17_max_writes = 392
pub const fake_g17_encode_ok = u32(0)
pub const fake_g17_encode_invalid_argument = u32(1)
pub const fake_g17_encode_write_capacity = u32(2)
pub const fake_g17_encode_stream_overflow = u32(3)
pub const fake_g17_encode_graph = u32(4)

// Inputs whose producer roots leave the recovered descriptor/command graph.
// Callers address them by producer offset through the setters below, keeping
// the generated table indices private to this ABI adapter.
pub struct FakeG17EncoderInputs {
pub mut:
	decisions [4][1]u8
	values    [4][5]u64
}

pub fn (mut inputs FakeG17EncoderInputs) set_decision(pass u32,
	producer_offset u32, taken bool) bool {
	if pass >= 4 || producer_offset != 0x2410 {
		return false
	}
	inputs.decisions[pass][0] = if taken { u8(1) } else { u8(0) }
	return true
}

pub fn (mut inputs FakeG17EncoderInputs) set_value(pass u32,
	producer_offset u32, value u64) bool {
	if pass >= 4 {
		return false
	}
	index := match producer_offset {
		0x1964 { 0 }
		0x1b04 { 1 }
		0x1bc4 { 2 }
		0x2148 { 3 }
		0x2394 { 4 }
		else { return false }
	}
	inputs.values[pass][index] = value
	return true
}

pub struct FakeG17Encoding {
pub:
	error       u32
	write_count u32
}

pub fn (result &FakeG17Encoding) succeeded() bool {
	return result.error == fake_g17_encode_ok
}

// One entry in the path-specific golden trace supplied by the command builder.
// Zero masks intentionally leave the corresponding value/template field
// unconstrained; selector, pass and mode are always exact.
pub struct FakeG17ExpectedWrite {
pub:
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

pub struct FakeG17AddressRange {
pub:
	address u64
	size    u64
}

pub struct FakeG17Submission {
pub:
	command             voidptr
	command_bytes       u64
	descriptor          voidptr
	descriptor_bytes    u64
	command_gpu_address u64
	writes              []FakeG17ExpectedWrite
	address_ranges      []FakeG17AddressRange
}

pub struct FakeG17Verification {
pub mut:
	observed        u64
	expected        u64
	error           u32
	pass            u32
	entry           u32
	observed_writes u32
	expected_writes u32
}

pub fn (report &FakeG17Verification) succeeded() bool {
	return report.error == fake_g17_ok
}

// Encode the recovered G17 3D event graph without allocation. The caller
// supplies a command-pool template in `command`, a fully staged descriptor,
// explicit values for the five external roots, and fixed-capacity golden
// storage. On success the first write_count entries can be passed directly to
// verify_fake_g17/submit_fake_g17.
@[markused]
pub fn encode_fake_g17_3d(command voidptr, command_bytes u64,
	descriptor voidptr, descriptor_bytes u64, command_gpu_address u64,
	inputs &FakeG17EncoderInputs, mut writes []FakeG17ExpectedWrite) FakeG17Encoding {
	if sizeof(FakeG17EncoderInputs) != C.vinix_fake_g17_encoder_inputs_size()
		|| writes.len > int(~u32(0)) {
		return FakeG17Encoding{
			error: fake_g17_encode_invalid_argument
		}
	}
	mut write_pointer := voidptr(0)
	if writes.len != 0 {
		unsafe {
			write_pointer = voidptr(&writes[0])
		}
	}
	mut write_count := u32(0)
	error := C.vinix_fake_g17_encode_3d(command, command_bytes, descriptor,
		descriptor_bytes, command_gpu_address, voidptr(inputs), write_pointer,
		u32(writes.len), &write_count)
	return FakeG17Encoding{
		error: u32(error)
		write_count: write_count
	}
}

// Verify exactly the writes selected for this command's recovered execution
// path.  The C core is allocation-free and is shared verbatim with the host
// test harness, while these slices make it convenient for the V encoder to
// provide its golden trace and live GPU address-space bounds.
@[markused]
pub fn verify_fake_g17(submission &FakeG17Submission) FakeG17Verification {
	mut report := FakeG17Verification{
		expected_writes: u32(submission.writes.len)
	}
	if sizeof(FakeG17ExpectedWrite) != C.vinix_fake_g17_expected_write_size()
		|| sizeof(FakeG17AddressRange) != C.vinix_fake_g17_address_range_size()
		|| sizeof(FakeG17Verification) != C.vinix_fake_g17_report_size() {
		report.error = fake_g17_invalid_argument
		return report
	}

	mut writes := voidptr(0)
	if submission.writes.len != 0 {
		writes = voidptr(&submission.writes[0])
	}
	mut ranges := voidptr(0)
	if submission.address_ranges.len != 0 {
		ranges = voidptr(&submission.address_ranges[0])
	}
	C.vinix_fake_g17_verify(submission.command, submission.command_bytes,
		submission.descriptor, submission.descriptor_bytes,
		submission.command_gpu_address, writes, u32(submission.writes.len),
		ranges, u32(submission.address_ranges.len), voidptr(&report))
	return report
}

// Submit to the common host queue and immediately inject the completion event
// produced by verification.  Queue ownership, fence wakeups, and teardown are
// therefore exercised without pretending that G17 firmware ran the command.
@[markused]
pub fn submit_fake_g17(mut queue workqueue.WorkQueue, item &workqueue.WorkItem,
	submission &FakeG17Submission) FakeG17Verification {
	slot := queue.submit(item) or {
		if item.fence != unsafe { nil } {
			syncobj.signal_error(item.fence, -16)
		}
		return FakeG17Verification{
			error: fake_g17_queue_full
			expected_writes: u32(submission.writes.len)
		}
	}
	report := verify_fake_g17(submission)
	queue.complete(slot, if report.succeeded() {
		workqueue.work_err_none
	} else {
		workqueue.work_err_channel_error
	})
	return report
}
