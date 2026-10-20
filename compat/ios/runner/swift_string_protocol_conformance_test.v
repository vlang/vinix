// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import strconv

#include <dlfcn.h>

$if macos {
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dladdr(voidptr, voidptr) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type SpLookup = fn (u64, u64, u64) u64
type SpInstantiate = fn (u64, u64, u64)

struct SpRequirement {
	flags         u32
	parameter     string
	target        string
	protocol_name string
}

struct SpDeclaration {
	name         string
	flags        u32
	associated   string
	signature    []SpRequirement
	requirements []u32
	defaults     []bool
}

fn sp_relative(field u64) u64 {
	// Symbolic references inside a mangled name are not word-aligned.
	mut bits := u32(0)
	for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(field + i)) }) << u32(i * 8) }
	return u64(i64(field) + i64(i32(bits)))
}

fn sp_text(address u64) string { return unsafe { (&char(address)).vstring() } }

fn sp_indirect(field u64) u64 {
	target := sp_relative(field)
	return if target & 1 != 0 { read64(target - 1) } else { target }
}

fn sp_mangled(address u64) string {
	mut text := ''
	mut offset := u64(0)
	for offset < 512 {
		byte := unsafe { *(&u8(address + offset)) }
		if byte == 0 { return text }
		if byte < 32 {
			assert byte == 1 || byte == 2
			mut target := sp_relative(address + offset + 1)
			if byte == 2 { target = read64(target) }
			mut info := [4]u64{}
			assert C.dladdr(voidptr(target), unsafe { &info[0] }) != 0
			symbol := sp_text(info[2])
			assert symbol.starts_with('$s') && (symbol.ends_with('Mn') || symbol.ends_with('Mp'))
			text += symbol[2..symbol.len - 2]
			offset += 5
		} else {
			text += rune(byte).str()
			offset++
		}
	}
	panic('unbounded native mangling')
}

fn sp_schema() []SpDeclaration {
	path := $if macos { os.real_path(os.dir(@FILE) + '/../../../tests/ios/string-protocol-schema.json') } $else { '/opt/ios/string-protocol-schema.json' }
	return json2.decode[[]SpDeclaration](os.read_file(path) or { panic(err) }) or { panic(err) }
}

fn sp_native(declarations []SpDeclaration) {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		descriptor := u64(C.dlsym(core, c'$sSSSysMc'))
		metadata := u64(C.dlsym(core, c'$sSSN'))
		root := u64(C.dlsym(core, c'$sSyMp'))
		assert descriptor != 0 && metadata != 0 && root != 0
		assert sp_indirect(descriptor) == root && sp_relative(descriptor + 4) == read64(metadata + 8)
		assert read32(descriptor + 12) == 0x20000 && read32(descriptor + 16) == 0x1001b
		pattern := sp_relative(descriptor + 8)
		assert read64(pattern) == descriptor && read64(pattern + 8) == 0
		lookup := unsafe { SpLookup(C.dlsym(core, c'swift_getWitnessTable')) }
		table := lookup(descriptor, metadata, 0)
		assert table != pattern && read64(table) == descriptor && read64(table + 8) != 0
		mut queue := [root]
		mut seen := map[u64]bool{}
		mut index := 0
		for queue.len > 0 {
			address := queue[0]
			queue.delete(0)
			if address in seen { continue }
			seen[address] = true
			expected := declarations[index]
			assert sp_text(sp_relative(address + 8)) == expected.name && read32(address) == expected.flags
			assert read32(address + 12) == u32(expected.signature.len) && read32(address + 16) == u32(expected.requirements.len)
			assert if read32(address + 20) == 0 { '' } else { sp_text(sp_relative(address + 20)) } == expected.associated
			for i, r in expected.signature {
				field := address + 24 + u64(i * 12)
				assert read32(field) == r.flags && sp_mangled(sp_relative(field + 4)) == r.parameter
				if r.protocol_name != '' {
					target := sp_indirect(field + 8)
					assert sp_text(sp_relative(target + 8)) == r.protocol_name
					queue << target
				} else {
					assert sp_mangled(sp_relative(field + 8)) == r.target
				}
			}
			for i, flags in expected.requirements {
				field := address + 24 + u64(expected.signature.len * 12 + i * 8)
				assert read32(field) == flags && (read32(field + 4) != 0) == expected.defaults[i]
			}
			index++
		}
		assert index == 20
		println('NATIVE-STRING-PROTOCOL: concrete String conformance, 27-word generic pattern requiring instantiation, seven inherited conformances, and twenty declaration/signature/requirement schemas matched; template differs from usable native table')
	}
}

fn sp_layout(descriptor u64, declarations []SpDeclaration) {
	assert read32(descriptor + 12) == 0x20008 && read32(descriptor + 16) == 0x1001b && read32(descriptor + 24) == 0
	assert read64(sp_relative(descriptor + 8)) == descriptor
	assert sp_indirect(descriptor + 4) == read64(swift_string_metadata() + 8)
	root := sp_indirect(descriptor)
	assert sp_text(sp_relative(root + 8)) == 'StringProtocol'
	assert read32(root + 12) == 20 && read32(root + 16) == 26 && read64(sp_relative(descriptor + 8) + 8) == 0
	assert sp_relative(descriptor + 20) == ios_runtime.swift_string_protocol_arena
	assert declarations.len == swift_string_protocol_schema_nodes.len
	for i, node in swift_string_protocol_schema_nodes {
		expected := declarations[i]
		address := descriptor + node.offset
		assert node.name == expected.name && read32(address) == expected.flags && sp_text(sp_relative(address + 8)) == expected.name
		assert sp_text(sp_relative(sp_relative(address + 4) + 8)) == 'Swift'
		assert read32(address + 12) == u32(expected.signature.len) && read32(address + 16) == u32(expected.requirements.len)
		assert if read32(address + 20) == 0 { '' } else { sp_text(sp_relative(address + 20)) } == expected.associated
		for j, r in expected.signature {
			field := address + 24 + u64(j * 12)
			assert read32(field) == r.flags && sp_text(sp_relative(field + 4)) == r.parameter
			if r.protocol_name != '' {
				destination := sp_indirect(field + 8)
				assert sp_text(sp_relative(destination + 8)) == r.protocol_name
			} else {
				assert sp_text(sp_relative(field + 8)) == r.target
			}
		}
		for j, flags in expected.requirements {
			field := address + 24 + u64(expected.signature.len * 12 + j * 8)
			assert read32(field) == flags && (read32(field + 4) != 0) == expected.defaults[j]
			if expected.defaults[j] {
				assert sp_relative(field + 4) == ios_runtime.swift_string_protocol_arena + 16
			}
		}
		actual := read64(descriptor + node.cell)
		assert sp_text(sp_relative(actual + 8)) == node.name
		if node.name == 'Hashable' {
			assert actual == swift_integer_metadata() - 16 + 352
		}
		if node.name == 'Equatable' {
			assert actual == swift_integer_metadata() - 16 + 432
		}
	}
}

fn sp_mapping(address u64, length u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + length <= start + size
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert mapped && address + length <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found == mapped
	}
}

fn sp_rejection(descriptor u64, guard u64) {
	for metadata in [u64(0), 1, guard, swift_string_metadata()]! {
		for arguments in [u64(0), guard, ~u64(0)]! {
			for _ in 0 .. 32 {
				if _ := swift_witness_table_checked(descriptor, metadata, arguments) {
					assert false
				} else {
					assert err.msg() == 'iOS: Swift StringProtocol witness instantiation is not implemented'
				}
			}
		}
	}
	instantiate := unsafe { SpInstantiate(voidptr(sp_relative(descriptor + 20))) }
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0])
		assert C.dup2(fds[1], 2) == 2
		C.close(fds[1])
		instantiate(guard, guard, guard)
		C._exit(0)
	}
	C.close(fds[1])
	mut bytes := [16384]u8{}
	mut length := 0
	for {
		assert length < bytes.len
		count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		length += int(count)
	}
	C.close(fds[0])
	mut status := i32(0)
	assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
	output := unsafe { tos(&bytes[0], length) }
	assert output.contains('iOS: Swift StringProtocol witness instantiation is not implemented') && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
}

fn sp_reader() u64 {
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		current := swift_string_protocol_descriptor_checked() or { panic(err) }
		if descriptor == 0 {
			descriptor = current
		} else {
			assert current == descriptor
		}
		assert read32(current + 16) == 0x1001b
	}
	return descriptor
}

fn test_swift_string_protocol_conformance_descriptor() {
	declarations := sp_schema()
	sp_native(declarations)
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	if _ := swift_string_protocol_descriptor_checked() {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn sp_reader() }
		resolved := workers.wait()
		descriptor := resolved[0]
		for address in resolved {
			assert address == descriptor && address != 0
		}
		unsafe {
			workers.free()
			resolved.free()
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSSSysMc') or { panic(err) } == descriptor
		sp_layout(descriptor, declarations)
		code := ios_runtime.swift_string_protocol_arena
		size := swift_string_protocol_allocation_size()
		sp_mapping(code, u64(page), true, true)
		sp_mapping(descriptor, u64(swift_string_protocol_schema_words.len * 8), true, false)
		sp_rejection(descriptor, guard)
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSSSysMc') == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSSSysMc') == none
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.swift_string_protocol_arena == 0 && ios_runtime.swift_string_protocol_descriptor == descriptor
		if _ := swift_string_protocol_descriptor_checked() {
			assert false
		}
		if _ := swift_witness_table_checked(descriptor, guard, guard) {
			assert false
		} else {
			assert err.msg() == 'iOS: Swift StringProtocol witness instantiation is not implemented'
		}
		sp_mapping(code, u64(page), false, true)
		sp_mapping(code + u64(page), size - u64(page), false, false)
	}
	assert C.munmap(voidptr(guard), page) == 0
	println('IOS-STRING-PROTOCOL: native declaration schema, sealed conformance/control records, canonical inherited identities, private uninstantiated pattern, diagnostic callback with protected arguments, checked/stale witness rejection, eight cold readers and two drained/unmapped lifetimes; StringProtocol witness operations remain unsupported')
}
