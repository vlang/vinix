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

fn C.vinix_fake_g17_expected_write_size() u64
fn C.vinix_fake_g17_address_range_size() u64
fn C.vinix_fake_g17_report_size() u64
fn C.vinix_fake_g17_verify(command voidptr, command_bytes u64,
	descriptor voidptr, descriptor_bytes u64, command_gpu_address u64,
	writes voidptr, write_count u32, ranges voidptr, range_count u32,
	report voidptr) int

pub const fake_g17_ok = u32(0)
pub const fake_g17_invalid_argument = u32(1)
pub const fake_g17_queue_full = u32(14)
pub const fake_g17_value_is_address = u32(1) << 0

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
