// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgcore

#include <sys/statvfs.h>
type C.fsblkcnt_t = u64

struct C.statvfs {
	f_bsize usize
	f_frsize usize
	f_bavail usize
}

fn fixture_max_count() u64 {
	// Darwin's fsblkcnt_t is narrower than Linux's, including on 64-bit hosts.
	assert sizeof(C.fsblkcnt_t) in [usize(4), 8]!
	return if sizeof(C.fsblkcnt_t) == 4 { u64(0xffffffff) } else { ~u64(0) }
}

// The V controller includes the real platform header before defining a
// function-like statvfs macro. Only calls are redirected; the native C struct
// layout remains intact. No test hook is compiled into the package service.
@[export: 'vinix_package_fixture_statvfs']
fn fixture_statvfs(path &char, output &C.statvfs) int {
	name := unsafe { tos3(path) }
	if name == '/fixture/error' { return -1 }
	unsafe {
		output.f_bsize = 4096
		output.f_frsize = 4096
		output.f_bavail = 3
		match name {
			'/fixture/large-io' { output.f_bsize = 65536 }
			'/fixture/small-io' { output.f_frsize = 65536 }
			'/fixture/byte-unit' { output.f_frsize = 1; output.f_bavail = fixture_max_count() }
			'/fixture/maximum' { output.f_frsize = ~u64(0) / fixture_max_count(); output.f_bavail = fixture_max_count() }
			'/fixture/overflow' { output.f_bsize = 1; output.f_frsize = ~u64(0); output.f_bavail = 2 }
			'/fixture/zero-unit' { output.f_frsize = 0 }
			'/fixture/zero-io' { output.f_bsize = 0 }
			'/fixture/empty' { output.f_bavail = 0 }
			else {}
		}
	}
	return 0
}

fn expected_space(name string, bytes u64, needed u64, admissible bool) ! {
	available := pkgcore.free_bytes('/fixture/' + name)!
	mut accepted := true
	pkgcore.disk_check(available, needed, 0) or { accepted = false }
	println('${name}: available=${available} expected=${bytes} admissible=${accepted} expected=${admissible}')
	assert available == bytes && accepted == admissible
}

fn check() ! {
	expected_space('large-io', 3 * 4096, 16384, false)!
	expected_space('small-io', 3 * 65536, 131072, true)!
	expected_space('byte-unit', fixture_max_count(), fixture_max_count(), true)!
	expected_space('maximum', ~u64(0), ~u64(0), true)!
	expected_space('empty', 0, 1, false)!
	expected_space('equal-units', 3 * 4096, 3 * 4096, true)!
	expected_space('zero-io', 3 * 4096, 3 * 4096, true)!
	for name in ['overflow', 'zero-unit', 'error'] {
		expected := match name {
			'overflow' { 'available disk space overflow' }
			'zero-unit' { 'invalid allocation unit' }
			else { 'cannot determine available disk space' }
		}
		mut refused := false
		pkgcore.free_bytes('/fixture/' + name) or {
			refused = true
			assert err.msg().contains('/fixture/' + name) && err.msg().contains(expected)
		}
		assert refused, name
	}
	println('Package space: allocation units, thresholds, zero availability, invalid units, overflow and syscall failure passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
