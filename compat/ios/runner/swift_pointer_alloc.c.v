// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift static method: signed capacity x0, Pointee metadata x1, pointer x0.
// Allocation needs only the value layout, including for noncopyable elements;
// no value witness is called and no element or ARC ownership is initialized.
fn swift_pointer_allocate_checked(count i64, metadata u64) !u64 {
	if count < 0 || metadata < 8 || metadata & 7 != 0 {
		return swift_raw_allocation_failure()
	}
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 { return swift_raw_allocation_failure() }
	size := read64(witness + 64); stride := read64(witness + 72)
	flags := read32(witness + 80); alignment := u64(flags & 255) + 1
	if flags & 0x00400000 != 0 || stride == 0 || size > stride
		|| alignment & (alignment - 1) != 0 || stride & (alignment - 1) != 0
		|| stride > 0x7fffffffffffffff || u64(count) > 0x7fffffffffffffff / stride {
		return swift_raw_allocation_failure()
	}
	// Native Swift requests the default 16-byte manual allocation alignment
	// for layouts aligned at most 16, and the actual alignment above that.
	mask := if alignment <= 16 { u64(-1) } else { alignment - 1 }
	return swift_raw_allocate_checked(u64(count) * stride, mask)
}

fn swift_pointer_allocate(count i64, metadata u64) u64 {
	return swift_pointer_allocate_checked(count, metadata) or { panic(err) }
}
