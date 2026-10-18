// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr
$if macos { fn C.setprogname(&char) }

type PrognameGet = fn () &char

fn pn_read(get PrognameGet, expected u64, text &char, id int) {
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		C.feclearexcept(C.FE_ALL_EXCEPT)
		C.feraiseexcept(C.FE_DIVBYZERO | C.FE_INEXACT)
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		darwin_set_errno(70 + id)
		for _ in 0 .. 1024 {
			assert u64(get()) == expected && C.strcmp(get(), text) == 0
		}
		assert C.fegetround() == rounding && C.fetestexcept(C.FE_ALL_EXCEPT) == flags && unsafe { *C.ios_errno_address() } == 70 + id
	}
}

fn pn_profile(get PrognameGet, value string, expected string, offset int) {
	page := u64(C.getpagesize())
	length := (u64(value.len + 1) + page - 1) & ~(page - 1)
	mapping := C.mmap(unsafe { nil }, usize(length + page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != unsafe { voidptr(-1) }
	source := u64(mapping) + length - u64(value.len + 1)
	C.memcpy(voidptr(source), value.str, usize(value.len))
	unsafe { *(&u8(source + u64(value.len))) = 0 }
	assert C.mprotect(mapping, usize(length), C.PROT_READ) == 0 && C.mprotect(voidptr(u64(mapping) + length), usize(page), C.PROT_NONE) == 0
	image_runtime_start(macho.Image{}, macho.Layout{}, 0)
	// These intentionally differ: getprogname follows argv[0], while the
	// executable path describes the configured image's canonical location.
	image_runtime.path = '/canonical/location/ActualExecutable'.clone()
	image_progname_start(unsafe { tos(&u8(source), value.len) })
	assert !image_runtime.started && u64(get()) == source + u64(offset)
	pn_read(get, source + u64(offset), expected.str, 0)
	mut workers := []thread{cap: 8}
	for id in 0 .. 8 { workers << spawn pn_read(get, source + u64(offset), expected.str, id) }
	workers.wait()
	unsafe { workers.free() }
	image_runtime_stop()
	assert image_runtime == unsafe { nil }
	assert C.munmap(mapping, usize(length + page)) == 0
}

fn pn_alias(get PrognameGet) {
	mut bytes := ('/dir/name' + '\x00').bytes()
	image_runtime_start(macho.Image{}, macho.Layout{}, 0)
	image_progname_start(unsafe { tos(bytes.data, bytes.len - 1) })
	pointer := u64(get())
	assert pointer == u64(bytes.data) + 5 && C.strcmp(get(), c'name') == 0
	bytes[6] = `/`
	bytes[0] = 0
	assert u64(get()) == pointer && C.strcmp(get(), c'n/me') == 0
	image_runtime_stop()
	unsafe { bytes.free() }
	assert image_runtime == unsafe { nil }
}

__global pn_fixture_seen = 0
__global pn_fixture_expected = u64(0)

fn pn_fixture_callback(phase i32, argc i32, argv &&char, address u64) i32 {
	assert pn_fixture_seen == phase && image_runtime != unsafe { nil } && image_runtime.started
	get := unsafe { PrognameGet(voidptr(address)) }
	assert address == u64(unsafe { voidptr(darwin_getprogname) }) && u64(get()) == pn_fixture_expected
	if phase < 2 {
		assert argc == 2 && argv != unsafe { nil }
		assert C.strcmp(get(), c'FortniteClient-IOS-Shipping') == 0
		if phase == 1 {
			// The returned pointer keeps referring to the original argument
			// even after the app replaces its argv[0] cell.
			unsafe { *(&u8(pn_fixture_expected)) = `G`; argv[0] = c'replaced-argv-cell' }
			assert u64(get()) == pn_fixture_expected && C.strcmp(get(), c'GortniteClient-IOS-Shipping') == 0
		}
	} else { assert C.strcmp(get(), c'GortniteClient-IOS-Shipping') == 0 }
	pn_fixture_seen++
	return 0
}

fn pn_put32(mut bytes []u8, at int, value u32) { for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) } }
fn pn_put64(mut bytes []u8, at int, value u64) { for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) } }
fn pn_text(mut bytes []u8, at int, value string) { for i, ch in value { bytes[at + i] = ch } }

fn pn_segment(mut bytes []u8, at int, name string, address u64, fileoff u64, prot u32, term bool) int {
	size := if term { 152 } else { 72 }
	pn_put32(mut bytes, at, 0x19); pn_put32(mut bytes, at + 4, u32(size)); pn_text(mut bytes, at + 8, name)
	pn_put64(mut bytes, at + 24, address); pn_put64(mut bytes, at + 32, 0x4000)
	pn_put64(mut bytes, at + 40, fileoff); pn_put64(mut bytes, at + 48, 0x4000)
	pn_put32(mut bytes, at + 56, prot); pn_put32(mut bytes, at + 60, prot)
	if term {
		pn_put32(mut bytes, at + 64, 1); pn_text(mut bytes, at + 72, '__mod_term_func'); pn_text(mut bytes, at + 88, name)
		pn_put64(mut bytes, at + 104, address + 16); pn_put64(mut bytes, at + 112, 8)
		pn_put32(mut bytes, at + 120, u32(fileoff + 16)); pn_put32(mut bytes, at + 124, 3); pn_put32(mut bytes, at + 136, 10)
	}
	return at + size
}

// A real ARM64 Mach-O: classic binding resolves _getprogname, LC_ROUTINES_64
// runs an initializer, LC_MAIN enters, and a rebased termination pointer runs
// before unmapping. Each stub calls the typed test callback through its data.
fn pn_fixture() !macho.Image {
	mut bytes := []u8{len: 0x8000}
	defer { unsafe { bytes.free() } }
	base := u64(0x100000000)
	pn_put32(mut bytes, 0, 0xfeedfacf); pn_put32(mut bytes, 4, 0x100000c); pn_put32(mut bytes, 12, 2)
	pn_put32(mut bytes, 16, 8); pn_put32(mut bytes, 24, 0x200085)
	mut at := pn_segment(mut bytes, 32, '__TEXT', base, 0, 5, false)
	at = pn_segment(mut bytes, at, '__DATA', base + 0x4000, 0x4000, 3, true)
	pn_put32(mut bytes, at, 0x1a); pn_put32(mut bytes, at + 4, 72); pn_put64(mut bytes, at + 8, base + 0x440); at += 72
	pn_put32(mut bytes, at, 0xc); pn_put32(mut bytes, at + 4, 56); pn_put32(mut bytes, at + 8, 24)
	pn_text(mut bytes, at + 24, '/usr/lib/libSystem.B.dylib'); at += 56
	pn_put32(mut bytes, at, 0x80000022); pn_put32(mut bytes, at + 4, 48)
	pn_put32(mut bytes, at + 8, 0x600); pn_put32(mut bytes, at + 12, 5)
	bind := [u8(0x11), 0x40, `_`, `g`, `e`, `t`, `p`, `r`, `o`, `g`, `n`, `a`, `m`, `e`, 0, 0x51, 0x71, 0, 0x90, 0]!
	pn_put32(mut bytes, at + 16, 0x620); pn_put32(mut bytes, at + 20, u32(bind.len)); at += 48
	pn_put32(mut bytes, at, 0x80000028); pn_put32(mut bytes, at + 4, 24); pn_put64(mut bytes, at + 8, 0x400); at += 24
	pn_put32(mut bytes, at, 0x32); pn_put32(mut bytes, at + 4, 24); pn_put32(mut bytes, at + 8, 2)
	pn_put32(mut bytes, at + 12, 0x110000); pn_put32(mut bytes, at + 16, 0x110000); at += 24
	// Legacy import inspection uses the undefined nlist entry; binding uses
	// the independent dyld opcode stream, as in linked Mach-O executables.
	pn_put32(mut bytes, at, 2); pn_put32(mut bytes, at + 4, 24)
	pn_put32(mut bytes, at + 8, 0x680); pn_put32(mut bytes, at + 12, 1)
	pn_put32(mut bytes, at + 16, 0x6a0); pn_put32(mut bytes, at + 20, 14); at += 24
	pn_put32(mut bytes, 0x680, 1); bytes[0x684] = 1; bytes[0x687] = 1
	pn_text(mut bytes, 0x6a1, '_getprogname')
	pn_put32(mut bytes, 20, u32(at - 32))
	for i, value in [u8(0x11), 0x21, 16, 0x51, 0]! { bytes[0x600 + i] = value }
	for i, value in bind { bytes[0x620 + i] = value }
	pn_put64(mut bytes, 0x4010, base + 0x480)
	pn_put64(mut bytes, 0x4018, u64(unsafe { voidptr(pn_fixture_callback) }))
	for pair in [[0x400, 1]!, [0x440, 0]!, [0x480, 2]!]! {
		for i, op in [u32(0xa9bf7bfd), 0x910003fd, 0xaa0103e2, 0x2a0003e1, 0x52800000 | (u32(pair[1]) << 5), 0x90000029, 0xf9400123, 0xf9400d30, 0xd63f0200, 0xa8c17bfd, 0xd65f03c0]! {
			pn_put32(mut bytes, pair[0] + i * 4, op)
		}
	}
	return macho.parse(bytes)!
}

fn pn_execute() ! {
	image := pn_fixture()!
	defer { module_image_free(image) }
	fixture_path := os.getenv('VINIX_IOS_PROGNAME_FIXTURE_DUMP')
	if fixture_path != '' { os.write_file(fixture_path, image.data.bytestr())! }
	imports := image.imported_symbols()!
	assert imports.len == 1 && imports[0].name == '_getprogname' && imports[0].library == '/usr/lib/libSystem.B.dylib'
	for _ in 0 .. 2 {
		mut bytes := ('/tmp/Raw.app/../FortniteClient-IOS-Shipping' + '\x00').bytes()
		argument := unsafe { tos(bytes.data, bytes.len - 1) }
		pn_fixture_seen = 0
		pn_fixture_expected = u64(bytes.data) + u64(argument.len - 'FortniteClient-IOS-Shipping'.len)
		assert execute(image, [argument, 'ignored-argument'])! == 0
		assert pn_fixture_seen == 3 && image_runtime == unsafe { nil } && module_runtime == unsafe { nil } && system_data == unsafe { nil } && ios_runtime.live == 0
		unsafe { bytes.free() }
	}
}

fn pn_reject(mode string) {
	if mode != 'uninitialized' {
		image_runtime_start(macho.Image{}, macho.Layout{}, 0)
		if mode == 'retired' { image_progname_start('Old.app/Old'); image_runtime_stop() }
	}
	darwin_getprogname()
	assert false
}

fn test_progname() {
	mode := os.getenv('VINIX_IOS_PROGNAME_CHILD')
	if mode != '' { pn_reject(mode) }
	assert image_runtime == unsafe { nil }
	address := runtime_symbol('/usr/lib/libSystem.B.dylib', '_getprogname') or { panic(err) }
	get := unsafe { PrognameGet(voidptr(address)) }
	for pair in [['', '']!, ['plain', 'plain']!, ['/', '']!, ['////', '']!, ['trailing/', '']!, ['./relative/../Game', 'Game']!, ['/Applications/Привет.app/новый', 'новый']!]! {
		pn_profile(get, pair[0], pair[1], pair[0].len - pair[1].len)
	}
	long_path := '/Applications/' + 'a'.repeat(8192) + '/FortniteClient-IOS-Shipping'
	pn_profile(get, long_path, 'FortniteClient-IOS-Shipping', long_path.len - 'FortniteClient-IOS-Shipping'.len)
	unsafe { long_path.free() }
	pn_profile(get, 'prefix/name\x00/ignored', 'name', 7)
	pn_alias(get)
	$if macos {
		native := unsafe { PrognameGet(C.dlsym(voidptr(-2), c'getprogname')) }
		original := native()
		for value in ['/tmp/Example.app/FortniteClient-IOS-Shipping', 'plain', 'trailing/', '']! {
			C.setprogname(value.str)
			pn_read(native, u64(value.str) + u64(value.len - value.all_after_last('/').len), value.all_after_last('/').str, 0)
		}
		mut storage := ('/dir/name' + '\x00').bytes()
		C.setprogname(unsafe { &char(storage.data) })
		pointer := u64(native()); storage[6] = `/`; storage[0] = 0
		pn_read(native, pointer, c'n/me', 0)
		C.setprogname(original)
		unsafe { storage.free() }
	}
	pn_execute()!
	for rejected in ['uninitialized', 'unconfigured', 'retired']! {
		mut child := os.new_process(os.executable())
		mut environment := os.environ(); environment['VINIX_IOS_PROGNAME_CHILD'] = rejected
		child.set_environment(environment); child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		assert code != 0 && output.contains('iOS: program name requires a configured main image') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
		mut rejected := false; runtime_symbol(library, '_getprogname') or { rejected = true }; assert rejected
	}
	println('IOS-PROGNAME: native borrowed basename, bounded guarded UTF-8/long/empty/NUL inputs, stable mutable argv alias, unchanged errno/fenv, eight readers, scoped import, invalid-state rejection and two real Mach-O initializer/main/destructor executions passed')
}
