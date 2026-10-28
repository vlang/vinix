// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

fn test_swift_mangled_probe_boundaries_and_scope() {
	previous := module_runtime
	mut runtime := ModuleRuntime{}
	defer { module_runtime = previous }
	objc_start()
	defer { objc_stop() }
	path := os.getenv('TMPDIR') + '/swift-type-probe-' + os.getpid().str() + '.log'
	defer { os.rm(path) or {} }
	fd := C.open(path.str, C.O_CREAT | C.O_TRUNC | C.O_RDWR, 384)
	assert fd >= 0
	saved := C.dup(2)
	assert saved >= 0 && C.dup2(fd, 2) == 2
	defer { C.dup2(saved, 2); C.close(saved); C.close(fd) }
	for initialized in [false, true] {
		module_runtime = if initialized { unsafe { &runtime } } else { unsafe { nil } }
		darwin_set_errno(37)
		// Disabled probes do not touch even an inaccessible name span.
		swift_mangled_probe(1, 3, 1, 1)
		assert unsafe { *C.ios_errno_address() } == 37
	}
	assert C.lseek(fd, 0, 1) == 0
	runtime.probe_no_ads = true
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0 }
	assert C.mprotect(unsafe { voidptr(base + u64(page)) }, page, C.PROT_NONE) == 0
	boundary := base + u64(page) - 3
	C.memcpy(unsafe { voidptr(boundary) }, c'SSx', 3)
	darwin_set_errno(37)
	if _ := swift_mangled_lookup_checked(boundary, 3, base + u64(page), base + u64(page)) {
		assert false, 'unsupported suffix accepted'
	}
	assert unsafe { *C.ios_errno_address() } == 37
	// The two length-invalid inputs must not read their pointer; zero length
	// at a protected page also reads nothing. Embedded NULs remain visible.
	swift_mangled_probe(0, 1, 0, 0)
	swift_mangled_probe(1, 1048577, 0, 0)
	swift_mangled_probe(~u64(0) - 1, 2, 0, 0)
	swift_mangled_probe(base + u64(page), 0, 0, 0)
	mut bytes := [66]u8{}
	for i in 0 .. bytes.len { bytes[i] = u8(i) }
	swift_mangled_probe(u64(unsafe { &bytes[0] }), 66, 1, 1)
	assert unsafe { *C.ios_errno_address() } == 37
	// Successful lookups do not produce diagnostics.
	assert swift_mangled_lookup_checked(u64(c'Si'), 2, 0, 0)! == swift_integer_metadata()
	assert C.close(2) == 0
	swift_mangled_probe(boundary, 3, 0, 0)
	assert unsafe { *C.ios_errno_address() } == 37
	assert C.dup2(saved, 2) == 2
	lines := os.read_file(path)!.trim_space().split_into_lines()
	assert lines.len == 6
	assert lines.all(it.starts_with('IOS-PROBE-SWIFT-TYPE: name=0x'))
	assert lines[0].contains(' length=3 context=0x' + (base + u64(page)).hex())
	assert lines[0].ends_with(' copied=3 bytes=535378')
	for i in 1 .. 5 { assert lines[i].ends_with(' copied=0 bytes=') }
	assert lines[5].ends_with(' copied=64 bytes=' + bytes[..64].hex())
	println('IOS-SWIFT-TYPE-PROBE: opt-in failed lookup, protected boundaries and unused pointers, raw NUL bytes, 64-byte cap, invalid lengths, successful-lookup silence and errno preservation PASS')
}
