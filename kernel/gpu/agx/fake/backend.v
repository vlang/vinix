// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fake

// Fake G17 execution stops at the firmware boundary: it verifies the encoded
// HAL300 3D register streams, then generates a host-side completion through the
// same WorkQueue/DmaFence path used by a real backend.  It deliberately does
// not emulate PMP, RTKit, UAT or G17 firmware acceptance.

import drm.syncobj
import gpu.agx.workqueue

#include "agx_fake_g17.h"

#include "agx_fake_g17_encode.h"

fn C.vinix_fake_g17_expected_write_size() usize

fn C.vinix_fake_g17_address_range_size() usize

fn C.vinix_fake_g17_resource_reference_size() usize

fn C.vinix_fake_g17_report_size() usize

fn C.vinix_fake_g17_encoder_inputs_size() usize

fn C.vinix_fake_g17_verify(command voidptr, command_bytes usize,
	descriptor voidptr, descriptor_bytes usize, command_gpu_address u64,
	writes &C.vinix_fake_g17_expected_write, write_count u32, ranges &C.vinix_fake_g17_address_range, range_count u32,
	resources &C.vinix_fake_g17_resource_reference, resource_count u32, report &C.vinix_fake_g17_report) i32

fn C.vinix_fake_g17_encode_3d(command voidptr, command_bytes usize,
	descriptor voidptr, descriptor_bytes usize, command_gpu_address u64,
	inputs &C.vinix_fake_g17_encoder_inputs, writes &C.vinix_fake_g17_expected_write, write_capacity u32, write_count &u32) i32

pub const fake_g17_ok = u32(0)
pub const fake_g17_invalid_argument = u32(1)
pub const fake_g17_queue_full = u32(17)
pub const fake_g17_value_is_address = u32(1) << 0
pub const fake_g17_vm_read = u32(1) << 0
pub const fake_g17_vm_write = u32(1) << 1
pub const fake_g17_external_event_count = 2
// Fixed output capacity for the recovered encoder. This is not the number of
// writes required by every job: write_count is descriptor/path dependent.
pub const fake_g17_max_writes = 404
pub const fake_g17_encode_ok = u32(0)
pub const fake_g17_encode_invalid_argument = u32(1)
pub const fake_g17_encode_write_capacity = u32(2)
pub const fake_g17_encode_stream_overflow = u32(3)
pub const fake_g17_encode_graph = u32(4)

// Inputs whose producer roots leave the recovered descriptor/command graph.
// Callers address them by producer offset through the setters below, keeping
// the generated table indices private to this ABI adapter. The two values are
// the parameter-management and USC private-memory pool addresses the kernel
// owns; column_count is the power-column count decoded from the GPU's
// cluster-configuration register (regs.GpuIdentity.column_count).
pub struct FakeG17EncoderInputs {
pub mut:
	values       [4][2]u64
	column_count u32
}

pub fn (mut inputs FakeG17EncoderInputs) set_value(pass u32,
	producer_offset u32, value u64) bool {
	if pass >= 4 {
		return false
	}
	index := match producer_offset {
		0x2148 { 0 }
		0x2394 { 1 }
		else {
			return false
		}
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
	address       u64
	size          u64
	access        u32
	object_handle u32
}

pub struct FakeG17ResourceReference {
pub:
	address           u64
	size              u64
	field             u32
	provenance        u32
	descriptor_member u32
	descriptor_bytes  u32
	access            u32
	reserved          u32
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
	resources           []FakeG17ResourceReference
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

// A successfully verified job remains installed in the common WorkQueue until
// its synthetic completion is delivered.  Keeping the slot explicit lets the
// fake driver exercise the same mapping/queue lifetime rules as asynchronous
// firmware without moving completion policy into the verifier.
pub struct FakeG17QueuedVerification {
pub:
	report  FakeG17Verification
	slot    u32
	pending bool
}

pub fn (report &FakeG17Verification) succeeded() bool {
	return report.error == fake_g17_ok
}

// Encode the recovered G17 3D event graph without allocation. The caller
// supplies a command-pool template in `command`, a fully staged descriptor,
// explicit values for the two external roots, and fixed-capacity golden
// storage. On success the first write_count entries can be passed directly to
// verify_fake_g17/submit_fake_g17.
@[markused]
pub fn encode_fake_g17_3d(command voidptr, command_bytes u64,
	descriptor voidptr, descriptor_bytes u64, command_gpu_address u64,
	inputs &FakeG17EncoderInputs, mut writes []FakeG17ExpectedWrite) FakeG17Encoding {
	// The normal call uses the fixed 404-write capacity. Compare unusually large
	// slices as u64: int(~u32(0)) is -1 because V's int is signed.
	if sizeof(FakeG17EncoderInputs) != C.vinix_fake_g17_encoder_inputs_size()
		|| u64(writes.len) > u64(~u32(0)) {
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
	error := unsafe { C.vinix_fake_g17_encode_3d(command, usize(command_bytes), descriptor, usize(descriptor_bytes), command_gpu_address, &C.vinix_fake_g17_encoder_inputs(inputs), &C.vinix_fake_g17_expected_write(write_pointer), u32(writes.len), &write_count) }
	return FakeG17Encoding{
		error:       u32(error)
		write_count: write_count
	}
}

// Verify exactly the writes selected for this command's recovered execution
// path.  The V core is allocation-free and is shared verbatim with the host
// test harness, while these slices make it convenient for the V encoder to
// provide its golden trace and live GPU address-space bounds.
@[markused]
pub fn verify_fake_g17(submission &FakeG17Submission) FakeG17Verification {
	mut report := FakeG17Verification{
		expected_writes: u32(submission.writes.len)
	}
	if sizeof(FakeG17ExpectedWrite) != C.vinix_fake_g17_expected_write_size()
		|| sizeof(FakeG17AddressRange) != C.vinix_fake_g17_address_range_size()
		|| sizeof(FakeG17ResourceReference) != C.vinix_fake_g17_resource_reference_size()
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
	mut resources := voidptr(0)
	if submission.resources.len != 0 {
		resources = voidptr(&submission.resources[0])
	}
	unsafe { C.vinix_fake_g17_verify(submission.command, usize(submission.command_bytes), submission.descriptor, usize(submission.descriptor_bytes), submission.command_gpu_address, &C.vinix_fake_g17_expected_write(writes), u32(submission.writes.len), &C.vinix_fake_g17_address_range(ranges), u32(submission.address_ranges.len), &C.vinix_fake_g17_resource_reference(resources), u32(submission.resources.len), &C.vinix_fake_g17_report(&report)) }
	return report
}

// Verify and install a job in the common host queue. Successful verification
// deliberately leaves the slot pending for the backend completion policy;
// verifier failures retire immediately with a fence error.
@[markused]
pub fn queue_fake_g17(mut queue workqueue.WorkQueue,
	item &workqueue.WorkItem,
	submission &FakeG17Submission) FakeG17QueuedVerification {
	slot := queue.submit(item) or {
		if item.fence != unsafe { nil } {
			syncobj.signal_error(item.fence, -16)
		}
		return FakeG17QueuedVerification{
			report: FakeG17Verification{
				error:           fake_g17_queue_full
				expected_writes: u32(submission.writes.len)
			}
		}
	}
	report := verify_fake_g17(submission)
	if !report.succeeded() {
		queue.complete(slot, workqueue.work_err_channel_error)
		return FakeG17QueuedVerification{
			report: report
			slot:   slot
		}
	}
	return FakeG17QueuedVerification{
		report:  report
		slot:    slot
		pending: true
	}
}

// Compatibility helper for callers that want immediate synthetic completion.
// The Mesa fake driver uses queue_fake_g17() so its valid work retires
// asynchronously and can exercise in-flight lifetime rules.
@[markused]
pub fn submit_fake_g17(mut queue workqueue.WorkQueue, item &workqueue.WorkItem,
	submission &FakeG17Submission) FakeG17Verification {
	queued := queue_fake_g17(mut queue, item, submission)
	if queued.pending {
		queue.complete(queued.slot, workqueue.work_err_none)
	}
	return queued.report
}
