// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.sysconf(int) i64
fn C.ios_errno_address() &i32

enum SysctlHardware {
	processors
	active_processors
	pagesize
	named_pagesize
	memory
	byteorder
	cpu_type
	cpu_subtype
	cpu_family
	arm64
	neon
	floatingpoint
}

fn sysctl_named_kind(name &char) ?SysctlHardware {
	// Compare the caller's C string in place: repeated queries allocate nothing.
	if darwin_strcmp(name, c'hw.ncpu') == 0
		|| darwin_strcmp(name, c'hw.physicalcpu_max') == 0
		|| darwin_strcmp(name, c'hw.logicalcpu_max') == 0 {
		return .processors
	}
	if darwin_strcmp(name, c'hw.activecpu') == 0
		|| darwin_strcmp(name, c'hw.physicalcpu') == 0
		|| darwin_strcmp(name, c'hw.logicalcpu') == 0 {
		return .active_processors
	}
	if darwin_strcmp(name, c'hw.pagesize') == 0 { return .named_pagesize }
	if darwin_strcmp(name, c'hw.memsize') == 0 { return .memory }
	if darwin_strcmp(name, c'hw.byteorder') == 0 { return .byteorder }
	if darwin_strcmp(name, c'hw.cputype') == 0 { return .cpu_type }
	if darwin_strcmp(name, c'hw.cpusubtype') == 0 { return .cpu_subtype }
	if darwin_strcmp(name, c'hw.cpufamily') == 0 { return .cpu_family }
	if darwin_strcmp(name, c'hw.optional.arm64') == 0 { return .arm64 }
	if darwin_strcmp(name, c'hw.optional.neon') == 0 { return .neon }
	if darwin_strcmp(name, c'hw.optional.floatingpoint') == 0 { return .floatingpoint }
	return none
}

fn sysctl_read_hardware(kind SysctlHardware, old voidptr, old_length &usize, new_value voidptr, new_length usize) i32 {
	previous := unsafe { *C.ios_errno_address() }
	// A zero-length new value, or a null new pointer, is a read on Darwin.
	if new_value != unsafe { nil } && new_length != 0 {
		darwin_set_errno(1)
		return -1
	}
	mut value := u64(0)
	mut size := usize(4)
	match kind {
		.processors, .active_processors {
			count := C.sysconf(if kind == .processors {
				int(C._SC_NPROCESSORS_CONF)
			} else {
				int(C._SC_NPROCESSORS_ONLN)
			})
			if count <= 0 || count > 2147483647 {
				darwin_set_errno(2)
				return -1
			}
			value = u64(count)
		}
		.pagesize, .named_pagesize {
			value = u64(C.getpagesize())
			if kind == .named_pagesize { size = 8 }
		}
		.memory {
			size = 8
			pages := C.sysconf(C._SC_PHYS_PAGES)
			page_size := u64(C.getpagesize())
			if pages <= 0 || page_size == 0 || u64(pages) > ~u64(0) / page_size {
				darwin_set_errno(2)
				return -1
			}
			value = u64(pages) * page_size
		}
		.byteorder { value = 1234 }
		.cpu_type { value = 0x100000c }
		.cpu_subtype, .cpu_family { value = 0 }
		.arm64, .neon, .floatingpoint { value = 1 }
	}
	available := if old_length == unsafe { nil } { usize(0) } else { unsafe { *old_length } }
	if old != unsafe { nil } {
		// Darwin's quad handler accepts a four-byte destination when the value
		// fits. It reports ERANGE without writing if narrowing would lose bits.
		if size == 8 && available == 4 {
			if value > 0xffffffff {
				darwin_set_errno(34)
				return -1
			}
			size = 4
		}
		if available < size {
			// Fixed-width hardware values are never copied as a partial prefix.
			if old_length != unsafe { nil } { unsafe { *old_length = 0 } }
			darwin_set_errno(12)
			return -1
		}
		unsafe { C.memcpy(old, &value, size) }
	}
	if old_length != unsafe { nil } { unsafe { *old_length = size } }
	darwin_set_errno(previous)
	return 0
}

fn darwin_sysctl(name &i32, count u32, old voidptr, old_length &usize, new_value voidptr, new_length usize) i32 {
	if count < 2 || count > 12 {
		darwin_set_errno(22)
		return -1
	}
	if name == unsafe { nil } {
		darwin_set_errno(14)
		return -1
	}
	if unsafe { name[0] } != 6 {
		darwin_set_errno(2)
		return -1
	}
	kind := match unsafe { name[1] } {
		3 { SysctlHardware.processors }
		4 { SysctlHardware.byteorder }
		7 { SysctlHardware.pagesize }
		24 { SysctlHardware.memory }
		25 { SysctlHardware.active_processors }
		else {
			darwin_set_errno(2)
			return -1
		}
	}
	if count != 2 {
		darwin_set_errno(21)
		return -1
	}
	return sysctl_read_hardware(kind, old, old_length, new_value, new_length)
}

fn darwin_sysctlbyname(name &char, old voidptr, old_length &usize, new_value voidptr, new_length usize) i32 {
	if name == unsafe { nil } {
		darwin_set_errno(22)
		return -1
	}
	kind := sysctl_named_kind(name) or {
		darwin_set_errno(2)
		return -1
	}
	return sysctl_read_hardware(kind, old, old_length, new_value, new_length)
}

fn darwin_errno() &i32 { return C.ios_errno_address() }

fn darwin_set_errno(value int) {
	location := C.ios_errno_address()
	unsafe { *location = i32(value) }
}

fn darwin_sysconf(name i32) i64 {
	$if linux {
		kind := match name {
			1 { int(C._SC_ARG_MAX) }
			2 { int(C._SC_CHILD_MAX) }
			3 { int(C._SC_CLK_TCK) }
			5 { int(C._SC_OPEN_MAX) }
			29 { int(C._SC_PAGESIZE) }
			57 { int(C._SC_NPROCESSORS_CONF) }
			58 { int(C._SC_NPROCESSORS_ONLN) }
			200 { int(C._SC_PHYS_PAGES) }
			else {
				darwin_set_errno(22)
				return -1
			}
		}
		return C.sysconf(kind)
	}
	return C.sysconf(name)
}
