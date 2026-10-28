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
		swift_optional_probe(1, 2, 25, 8, 7, 0)
		swift_sequence_value_probe(1, 8, 8, 7, 1, 1, 1, 1)
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
	assert C.dup2(fd, 2) == 2
	// Only checked scalar snapshots reach the Optional diagnostic. Unreadable
	// metadata addresses are printable without introducing another read.
	if _ := swift_optional_access_checked(0, 1) { assert false }
	mut witness := [14]u64{}
	mut full := [u64(unsafe { &witness[0] }), 0x200, 0]!
	for i in 0 .. 8 { witness[i] = u64(unsafe { voidptr(swift_integer_copy) }) }
	witness[8] = 25
	witness[9] = 32
	witness[10] = 7
	wrapped := u64(unsafe { &full[1] })
	mut args := [wrapped]!
	context := swift_array_arena() + u64(page) + 160
	before := ios_runtime.swift_optional_metadata.len
	if _ := swift_mangled_lookup_checked(u64(c'xSg'), 3, context, u64(unsafe { &args[0] })) {
		assert false, 'oversized Optional accepted'
	}
	witness[8] = 8
	witness[10] = 0x20007
	if _ := swift_optional_access_checked(0, wrapped) { assert false }
	witness[10] = 7
	witness[7] = 0
	if _ := swift_optional_access_checked(0, wrapped) { assert false }
	assert ios_runtime.swift_optional_metadata.len == before
	// Successful Optional lookup remains silent, as do failed writes.
	assert swift_mangled_lookup_checked(u64(c'SiSg'), 4, 0, 0)! != 0
	assert C.close(2) == 0
	swift_optional_probe(base + u64(page), 2, 25, 8, 7, 0)
	assert unsafe { *C.ios_errno_address() } == 37
	assert C.dup2(saved, 2) == 2
	optional_lines := os.read_file(path)!.trim_space().split_into_lines()[6..]
	assert optional_lines.len == 5
	assert optional_lines[0] == 'IOS-PROBE-SWIFT-OPTIONAL: wrapped=0x1 stage=1 size=0 alignment=0 flags=0x0 extra=0'
	assert optional_lines[1].ends_with(' stage=2 size=25 alignment=8 flags=0x7 extra=0')
	assert optional_lines[2].ends_with(' copied=3 bytes=785367')
	assert optional_lines[3].ends_with(' stage=2 size=8 alignment=8 flags=0x20007 extra=0')
	assert optional_lines[4].ends_with(' stage=3 size=8 alignment=8 flags=0x7 extra=0')
	assert C.dup2(fd, 2) == 2
	witness[2] = 0
	if _ := swift_optional_access_checked(0, wrapped) { assert false }
	assert unsafe { *C.ios_errno_address() } == 37
	assert C.dup2(saved, 2) == 2
	value_lines := os.read_file(path)!.trim_space().split_into_lines()[11..]
	assert value_lines.len == 2
	assert value_lines[0].starts_with('IOS-PROBE-SWIFT-VALUE: metadata=0x')
	assert value_lines[0].contains(' size=8 stride=32 flags=0x7 copy=0x0 take=0x')
	assert value_lines[1].ends_with(' stage=1 size=0 alignment=0 flags=0x0 extra=0')
	println('IOS-SWIFT-TYPE-PROBE: opt-in failed lookup, protected boundaries and unused pointers, raw NUL bytes, 64-byte cap, invalid lengths, successful-lookup silence and errno preservation PASS')
	println('IOS-SWIFT-OPTIONAL-PROBE: checked rejection snapshots, bounded writes, pointer independence, rejected wrapper names, no publication, success silence and errno preservation PASS')
}
