// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Failed bounded lookups are visible only in the explicit startup probe.
// Symbolic names contain NULs, so record raw bytes rather than a C string.
// Fixed stack storage bounds the diagnostic and leaves errno unchanged even
// when stderr is closed. Context and argument pointers are never dereferenced.
fn swift_mangled_probe(name u64, length u64, context u64, generic_args u64) {
	if module_runtime == unsafe { nil } || !module_runtime.probe_no_ads { return }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	valid := name != 0 && length <= 1048576 && name <= ~u64(0) - length
	copied := if !valid { u64(0) } else if length < 64 { length } else { u64(64) }
	mut buffer := [512]char{}
	mut count := C.snprintf(unsafe { &buffer[0] }, buffer.len,
		c'IOS-PROBE-SWIFT-TYPE: name=0x%llx length=%llu context=0x%llx args=0x%llx copied=%llu bytes=',
		name, length, context, generic_args, copied)
	for index in u64(0) .. copied {
		if count < 0 || count >= buffer.len - 4 { return }
		count += C.snprintf(unsafe { &buffer[count] }, usize(buffer.len - count),
			c'%02x', u32(unsafe { *(&u8(name + index)) }))
	}
	if count > 0 && count < buffer.len - 1 {
		buffer[count] = char(10)
		C.write(2, unsafe { &buffer[0] }, usize(count + 1))
	}
}
