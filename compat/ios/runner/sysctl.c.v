// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.sysconf(int) i64
fn C.ios_errno_address() &i32

fn darwin_sysctlbyname(name &char, old voidptr, old_length &usize, new_value voidptr, new_length usize) int {
	_ = new_length
	if new_value != unsafe { nil } { darwin_set_errno(1); return -1 }
	if name == unsafe { nil } || old_length == unsafe { nil } { darwin_set_errno(22); return -1 }
	key := ctext(u64(name))
	mut value := u64(0)
	mut size := usize(4)
	match key {
		'hw.ncpu', 'hw.activecpu', 'hw.physicalcpu', 'hw.logicalcpu', 'hw.physicalcpu_max', 'hw.logicalcpu_max' {
			count := C.sysconf(C._SC_NPROCESSORS_ONLN)
			value = u64(if count > 0 { count } else { i64(1) })
		}
		'hw.cputype' { value = 0x100000c }
		'hw.cpusubtype', 'hw.cpufamily' { value = 0 }
		'hw.optional.arm64', 'hw.optional.neon', 'hw.optional.floatingpoint' { value = 1 }
		'hw.pagesize' { value = u64(C.getpagesize()) }
		'hw.memsize' {
			size = 8
			pages := C.sysconf(C._SC_PHYS_PAGES)
			if pages <= 0 { darwin_set_errno(2); return -1 }
			value = u64(pages) * u64(C.getpagesize())
		}
		else { darwin_set_errno(2); return -1 }
	}
	available := unsafe { *old_length }
	unsafe { *old_length = size }
	if old != unsafe { nil } {
		copied := if available < size { available } else { size }
		unsafe { C.memcpy(old, &value, copied) }
		if available < size { darwin_set_errno(12); return -1 }
	}
	return 0
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
			else { darwin_set_errno(22); return -1 }
		}
		return C.sysconf(kind)
	}
	return C.sysconf(name)
}
