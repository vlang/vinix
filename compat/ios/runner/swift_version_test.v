// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <sys/sysctl.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.sysctlbyname(&char, voidptr, &usize, voidptr, usize) i32
type VersionGet = fn () IosOperatingSystemVersion
type VersionProbe = fn (u64, u64, u64, &u64)

fn version_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_stdlib_operatingSystemVersion') or { panic(err) }
}
fn version_guarded(entry u64, probe VersionProbe, expected IosOperatingSystemVersion, context u64) {
	get := unsafe { VersionGet(voidptr(entry)) }
	assert get() == expected
	mut words := [u64(0x123456789abcdef0), 0xa5a5a5a5a5a5a5a5, 0xa5a5a5a5a5a5a5a5,
		0xa5a5a5a5a5a5a5a5, 0xfedcba9876543210]!
	mut seen := u64(0)
	darwin_set_errno(12345)
	probe(u64(unsafe { &words[1] }), entry, context, unsafe { &seen })
	assert unsafe { *darwin_errno() } == 12345 && seen == context
	assert words == [u64(0x123456789abcdef0), u64(expected.major), u64(expected.minor),
		u64(expected.patch), 0xfedcba9876543210]!
}
fn version_worker(entry u64, probe VersionProbe, expected IosOperatingSystemVersion, worker int) {
	for i in 0 .. 1024 { version_guarded(entry, probe, expected, u64(0xdeadbeefcafe0000) ^ u64(worker << 12 | i)) }
}
fn version_run(entry u64, probe VersionProbe, expected IosOperatingSystemVersion) {
	assert sizeof(IosOperatingSystemVersion) == 24
	version_guarded(entry, probe, expected, 0xfedcba9876543210)
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(region) }, page * 2) == 0 }
	assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_NONE) == 0
	// The result must write exactly 24 bytes, including both zero components.
	destination := region + u64(page) - 24
	C.memset(unsafe { voidptr(destination - 8) }, 0xa5, 32)
	mut context := u64(0)
	probe(destination, entry, 0x123456789abcdef0, unsafe { &context })
	assert context == 0x123456789abcdef0 && read64(destination - 8) == 0xa5a5a5a5a5a5a5a5
	assert read64(destination) == u64(expected.major) && read64(destination + 8) == u64(expected.minor) && read64(destination + 16) == u64(expected.patch)
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn version_worker(entry, probe, expected, i) }
	workers.wait()
}
fn test_swift_operating_system_version() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(code) }, page) == 0 }
	for i, instruction in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0303f3,
		0xaa0203f4, 0xaa0103f0, 0xaa0003e8, 0xd63f0200, 0xf9000274,
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), instruction) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 48) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { VersionProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'_swift_stdlib_operatingSystemVersion')); assert entry != 0
		mut bytes := [128]u8{}; mut length := usize(128)
		assert C.sysctlbyname(c'kern.osproductversion', unsafe { &bytes[0] }, &length, unsafe { nil }, 0) == 0
		parts := unsafe { (&bytes[0]).vstring() }.split('.')
		expected := IosOperatingSystemVersion{ major: parts[0].i64(), minor: parts[1].i64(), patch: if parts.len > 2 { parts[2].i64() } else { i64(0) } }
		version_run(entry, probe, expected)
		println('IOS-SWIFT-VERSION-NATIVE: installed OS version matches host sysctl, direct/indirect 24-byte return, guards and protected boundary, preserved Swift context/errno and eight workers')
	}
	early := version_resolve()
	version_guarded(early, probe, IosOperatingSystemVersion{ major: 17 }, 0xdeadbeef12345678)
	for _ in 0 .. 2 {
		objc_start()
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn version_resolve() }
		resolved := resolvers.wait()
		for address in resolved { assert address == early && address != 0 }
		mut frame := RegisterFrame{}
		device_class := ios_runtime.names['UIDevice']
		assert platform_framework_dispatch(device_class, 'currentDevice', mut frame)
		device := frame.x[0]
		assert platform_framework_dispatch(device, 'systemVersion', mut frame)
		text := frame.x[0]
		parts := string_text(text).split('.')
		expected := IosOperatingSystemVersion{ major: parts[0].i64(), minor: parts[1].i64(), patch: if parts.len > 2 { parts[2].i64() } else { i64(0) } }
		assert expected == IosOperatingSystemVersion{ major: 17 }
		// UIDevice's getter returns an autoreleased (+0) NSString. The pool
		// drains it at shutdown along with the device's singleton reference.
		version_run(resolved[0], probe, expected)
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_void_arena == 0
		assert ios_runtime.swift_arc_code == 0 && ios_runtime.swift_hash_code == 0 && ios_runtime.swift_fatal_code == 0
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		assert version_resolve() == early
		version_guarded(early, probe, expected, 0xfedcba9876543210)
	}
	println('IOS-SWIFT-VERSION: iOS 17.0.0 agrees with UIDevice, exact x8 result width, guards/protected boundary, preserved context/errno, canonical concurrent resolution, eight workers and two drained cycles without runtime arenas')
}
