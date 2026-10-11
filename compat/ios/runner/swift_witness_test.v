// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type WitnessLookup = fn (u64, u64, u64) u64
type WitnessProbe = fn (u64, u64, u64, u64, &u64)
type WitnessSign = fn (u64, u64) u64
type WitnessStrip = fn (u64) u64

fn witness_case(lookup WitnessLookup, probe WitnessProbe, descriptor u64, metadata u64, arguments u64, expected u64) {
	for _ in 0 .. 128 {
		mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
		probe(descriptor, metadata, arguments, u64(unsafe { voidptr(lookup) }), unsafe { &output[1] })
		assert output[0] == 0x1234 && output[4] == 0x5678
		assert output[1] == expected && output[2] == 0x5020 && output[3] == 0x5021
		assert lookup(descriptor, metadata, arguments) == expected
	}
}

fn witness_fixture(lookup WitnessLookup, probe WitnessProbe, native bool, sign WitnessSign, strip WitnessStrip) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	descriptor := base + u64(page) - 16
	protected := base + u64(page)
	assert C.mprotect(unsafe { voidptr(protected) }, page, C.PROT_NONE) == 0
	// End-of-page descriptor, unreadable unused input pointers and nonsense
	// protocol/type offsets prove the static lookup reads just pattern/flags.
	write32(descriptor, 0x80000000)
	write32(descriptor + 4, 0x80000000)
	for table in [base + 128, protected]! {
		for flags in [u32(0), 8, 16, 24, 64, 72, 80, 88]! {
			write32(descriptor + 12, flags)
			swift_protocol_relative(descriptor + 8, table)
			caller_descriptor := if native { sign(descriptor, 0xc6eb) } else { descriptor }
			// Native arm64e's table data pointer uses the same raw address here.
			assert strip(lookup(caller_descriptor, protected, protected)) == table
			witness_case(lookup, probe, caller_descriptor, protected, protected, table)
		}
	}
	write32(descriptor + 8, 0)
	write32(descriptor + 12, 0)
	witness_case(lookup, probe, if native { sign(descriptor, 0xc6eb) } else { descriptor }, 0, 0, 0)
	assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
}

fn witness_native(probe WitnessProbe, sign WitnessSign, strip WitnessStrip) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		lookup := unsafe { WitnessLookup(C.dlsym(lib, c'swift_getWitnessTable')) }
		for prefix in ['$sSiSHs', '$sSiSQs', '$sSSs20TextOutputStreamables',
			'$sSSs23CustomStringConvertibles']! {
			descriptor := u64(C.dlsym(lib, (prefix + 'Mc').str))
			table := u64(C.dlsym(lib, (prefix + 'WP').str))
			assert descriptor != 0 && table != 0
			witness_case(lookup, probe, descriptor, 0, 0, table)
		}
		witness_fixture(lookup, probe, true, sign, strip)
		println('IOS-SWIFT-WITNESS-NATIVE: canonical concrete Int and String tables, signed relative patterns, nullable tables, eight static flag combinations, guarded raw C calls preserving x20/x21, exact protected descriptor boundary and unread unused inputs/table bodies')
	}
}

fn witness_identity(value u64) u64 { return value }

fn witness_unsigned(value u64, _key u64) u64 { return value }

fn witness_reader(descriptor u64, table u64) {
	for _ in 0 .. 1024 {
		assert swift_witness_table(descriptor, 0, 0) == table
	}
}

fn witness_reject(descriptor u64) {
	if _ := swift_witness_table_checked(descriptor, 0, 0) {
		assert false, 'unsupported witness lookup accepted'
	}
}

fn witness_suite(probe WitnessProbe) {
	lookup := unsafe { WitnessLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getWitnessTable') or { panic(err) })) }
	mut pairs := [u64(0), 0]!
	for prefix in ['_$sSiSHs', '_$sSiSQs', '_$sSSs20TextOutputStreamables',
		'_$sSSs23CustomStringConvertibles']! {
		descriptor := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', prefix + 'Mc') or { panic(err) }
		table := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', prefix + 'WP') or { panic(err) }
		witness_case(lookup, probe, descriptor, 0, 0, table)
		pairs[0] = descriptor
		pairs[1] = table
	}
	witness_fixture(lookup, probe, false, witness_unsigned, witness_identity)
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	swift_protocol_relative(base + 8, base + 128)
	for flags in [u32(1), 0x20, 0x80, 0x100, 0x10000, 0x20000, 0x30000, 0x300c0, 0x40000, 0x80000,
		0x1000000, 0x80000000]! {
		write32(base + 12, flags)
		witness_reject(base)
	}
	write32(base + 12, 0)
	write32(base + 8, 1)
	witness_reject(base)
	witness_reject(0)
	witness_reject(1)
	witness_reject(~u64(0) - 3)
	assert C.munmap(unsafe { voidptr(base) }, page) == 0
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn witness_reader(pairs[0], pairs[1]) }
	workers.wait()
	assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
}

fn test_swift_witness_table() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	// PAC is confined to the native arm64e comparison fixtures.
	write32(code + 64, 0xdac10820)
	write32(code + 68, 0xd65f03c0)
	write32(code + 80, 0xdac147e0)
	write32(code + 84, 0xd65f03c0)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 88) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { WitnessProbe(voidptr(code)) }
	witness_native(probe, unsafe { WitnessSign(voidptr(code + 64)) }, unsafe { WitnessStrip(voidptr(code + 80)) })
	for _ in 0 .. 2 {
		objc_start()
		witness_suite(probe)
		objc_stop()
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_integer_arena == 0
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_array_metadata.len == 0
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-WITNESS: borrowed canonical concrete tables, both relative directions, nullable pattern, guarded C ABI, unread unused metadata/protocol/type/arguments/table bodies, exact protected boundaries, unsupported EOS resilient and foreign/conditional/generic records rejected, eight readers and two drained cycles')
}
