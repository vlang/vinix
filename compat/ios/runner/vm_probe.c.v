// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Only the explicit startup probe records VM calls. Keep this path usable when
// an allocation has failed: fixed stack storage, constant formats, no V strings.
// args follow the operation's ABI order, excluding address and size. Mach calls
// report the address-slot pointer; the final argument records its successful output.
fn vm_probe_record(operation &char, address u64, size u64, args [10]u64, result i64) {
	if module_runtime == unsafe { nil } || !module_runtime.probe_no_ads { return }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut buffer := [768]char{}
	length := C.snprintf(unsafe { &buffer[0] }, buffer.len,
		c'IOS-PROBE-VM: op=%s address=0x%llx size=0x%llx args=0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx,0x%llx result=0x%llx errno=%d\n',
		operation, address, size, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], u64(result), previous)
	if length > 0 && length < buffer.len { C.write(2, unsafe { &buffer[0] }, usize(length)) }
}

fn darwin_vm_allocate(task u32, address &u64, size u64, flags i32) i32 {
	result := darwin_vm_allocate_impl(task, address, size, flags)
	output := if result == 0 { unsafe { *address } } else { u64(0) }
	vm_probe_record(c'vm_allocate', u64(address), size, [u64(task), u64(u32(flags)), 0, 0, 0, 0, 0, 0, 0, output]!, result)
	return result
}

fn darwin_vm_map(task u32, address &u64, size u64, mask u64, flags i32, object u32, offset u64, copy i32, current i32, maximum i32, inheritance i32) i32 {
	result := darwin_vm_map_impl(task, address, size, mask, flags, object, offset, copy, current, maximum, inheritance)
	output := if result == 0 { unsafe { *address } } else { u64(0) }
	vm_probe_record(c'vm_map', u64(address), size, [u64(task), mask, u64(u32(flags)), u64(object), offset, u64(u32(copy)), u64(u32(current)), u64(u32(maximum)), u64(u32(inheritance)), output]!, result)
	return result
}

fn darwin_vm_deallocate(task u32, address u64, size u64) i32 {
	result := darwin_vm_deallocate_impl(task, address, size)
	vm_probe_record(c'vm_deallocate', address, size, [u64(task), 0, 0, 0, 0, 0, 0, 0, 0, 0]!, result)
	return result
}
