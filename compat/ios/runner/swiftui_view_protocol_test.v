// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.mincore(voidptr, usize, &u8) i32

$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self() u32
	fn C.vm_region_recurse_64(u32, &u64, &u64, &u32, &i32, &u32) i32
}

const view_protocol_library = '/System/Library/Frameworks/SwiftUI.framework/SwiftUI'

fn view_protocol_symbols() [8]string {
	return ['_$s7SwiftUI4ViewMp', '_$s7SwiftUI4ViewTL', '_$s7SwiftUI4ViewP4BodyAC_AaBTn',
		'_$s4Body7SwiftUI4ViewPTl',
		'_$s7SwiftUI4ViewP05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZTq',
		'_$s7SwiftUI4ViewP05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZTq',
		'_$s7SwiftUI4ViewP14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZTq',
		'_$s7SwiftUI4ViewP4body4BodyQzvgTq']!
}

fn view_protocol_offsets() [8]u64 { return [u64(0), 28, 36, 44, 52, 60, 68, 76]! }

fn view_protocol_defaults() [3]string {
	return [
		'_$s7SwiftUI4ViewP05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZ',
		'_$s7SwiftUI4ViewP05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZ',
		'_$s7SwiftUI4ViewP14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZ',
	]!
}

fn view_protocol_diagnostics() [3]string {
	return ['iOS: SwiftUI View._makeView graph construction is not implemented',
		'iOS: SwiftUI View._makeViewList graph construction is not implemented',
		'iOS: SwiftUI View._viewListCount graph traversal is not implemented']!
}

type ViewProtocolProbe = fn (&u64, u64, &u64)

fn view_protocol_relative(field u64) u64 {
	mut bits := u32(0)
	for i in u64(0) .. 4 {
		bits |= u32(unsafe { *(&u8(field + i)) }) << u32(i * 8)
	}
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn view_protocol_indirect(field u64) u64 {
	bits := i32(read32(field))
	target := u64(i64(field) + i64(bits & ~1))
	return if bits & 1 != 0 { read64(target) } else { target }
}

fn view_protocol_text(address u64) string {
	assert address != 0
	return unsafe { (&char(address)).vstring() }
}

fn view_protocol_permissions(address u64, bytes u64, executable bool, native bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [64]i32{}
		mut count := u32(C.VM_REGION_SUBMAP_INFO_COUNT_64)
		mut depth := u32(999)
		assert C.vm_region_recurse_64(C.mach_task_self(), &start, &size, &depth,
			unsafe { &info[0] }, &count) == 0
		assert start <= address && address + bytes <= start + size
		if native && !executable {
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
				assert address + bytes <= end
				assert fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found
	}
}

fn view_protocol_graph(descriptor u64, native bool) [3]u64 {
	assert descriptor != 0 && descriptor & 3 == 0
	view_protocol_permissions(descriptor, 84, false, native)
	assert read32(descriptor) == 0x30043
	module_descriptor := view_protocol_relative(descriptor + 4)
	assert read32(module_descriptor) == 0 && read32(module_descriptor + 4) == 0
	assert view_protocol_text(view_protocol_relative(module_descriptor + 8)) == 'SwiftUI'
	assert view_protocol_text(view_protocol_relative(descriptor + 8)) == 'View'
	assert read32(descriptor + 12) == 1 && read32(descriptor + 16) == 6
	assert view_protocol_text(view_protocol_relative(descriptor + 20)) == 'Body'
	assert read32(descriptor + 24) == 0x80
	assert view_protocol_indirect(descriptor + 32) == descriptor
	path := view_protocol_relative(descriptor + 28)
	for i, byte in [u8(`4`), `B`, `o`, `d`, `y`]! {
		assert unsafe { *(&u8(path + u64(i))) } == byte
	}
	assert unsafe { *(&u8(path + 5)) } == if native { u8(2) } else { u8(1) }
	path_target := view_protocol_relative(path + 6)
	assert (if native { read64(path_target) } else { path_target }) == descriptor
	assert view_protocol_text(path + 10) == 'Qz'
	mut defaults := [3]u64{}
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! {
		assert read32(descriptor + 36 + u64(i * 8)) == flags
		entry := view_protocol_relative(descriptor + 40 + u64(i * 8))
		if i >= 2 && i <= 4 {
			assert entry != 0
			view_protocol_permissions(entry, 4, true, native)
			for previous in 0 .. i - 2 {
				assert entry != defaults[previous]
			}
			defaults[i - 2] = entry
		} else {
			assert entry == 0
		}
	}
	return defaults
}

fn view_protocol_resolve() u64 {
	return runtime_symbol(view_protocol_library, '_$s7SwiftUI4ViewMp') or { panic(err) }
}

fn view_protocol_opacity() u64 {
	return runtime_symbol(view_protocol_library, '_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP') or { panic(err) }
}

fn view_protocol_never() u64 {
	return runtime_symbol(view_protocol_library, '_$ss5NeverO7SwiftUI4ViewACWP') or { panic(err) }
}

fn view_protocol_shared(descriptor u64, opacity u64, never u64) {
	conformance := read64(opacity)
	modifier := view_protocol_indirect(conformance)
	assert view_protocol_indirect(modifier + 32) == descriptor
	assert view_protocol_indirect(read64(never)) == descriptor
	assert view_protocol_relative(modifier + 4) == view_protocol_relative(descriptor + 4)
	nominal := view_protocol_relative(conformance + 4)
	assert view_protocol_relative(nominal + 4) == view_protocol_relative(descriptor + 4)
	assert read32(modifier) == 0x30043
	assert view_protocol_text(view_protocol_relative(modifier + 8)) == 'ViewModifier'
	assert view_protocol_text(view_protocol_relative(modifier + 20)) == 'Body'
}

fn view_protocol_empty() {
	assert ios_runtime.swiftui_opacity_arena == 0
	assert ios_runtime.swiftui_modified_arena == 0 && ios_runtime.swiftui_text_view_arena == 0
	assert ios_runtime.swiftui_environment_transform_arena == 0
	assert ios_runtime.swiftui_tuple_nominal_arena == 0 && ios_runtime.swiftui_vstack_nominal_arena == 0
	assert ios_runtime.swiftui_zstack_nominal_arena == 0 && ios_runtime.swiftui_button_nominal_arena == 0
	assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_void_arena == 0
	assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_heap.len == 0
	assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0
	assert ios_runtime.swift_strings.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
}

fn view_protocol_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(voidptr(address), page, &residency) == -1
	}
}

fn view_protocol_rejected() {
	for symbol in view_protocol_symbols() {
		assert swiftui_view_protocol_symbol(symbol) == none
	}
	for symbol in view_protocol_defaults() {
		assert swiftui_view_protocol_symbol(symbol) == none
	}
}

fn view_protocol_reader(first int) u64 {
	if first == 1 {
		assert view_protocol_opacity() != 0
	}
	if first == 2 {
		assert view_protocol_never() != 0
	}
	if first == 3 {
		assert runtime_symbol(view_protocol_library, view_protocol_symbols()[4]) or { panic(err) } != 0
	}
	if first == 4 {
		extension := view_protocol_defaults()[2].replace('4ViewP', '4ViewPAAE')
		assert runtime_symbol(view_protocol_library, extension) or { panic(err) } != 0
	}
	mut descriptor := u64(0)
	for _ in 0 .. 128 {
		descriptor = view_protocol_resolve()
		for i, symbol in view_protocol_symbols() {
			assert runtime_symbol(view_protocol_library, symbol) or { panic(err) } == descriptor + view_protocol_offsets()[i]
		}
		view_protocol_shared(descriptor, view_protocol_opacity(), view_protocol_never())
	}
	return descriptor
}

fn view_protocol_terminal(probe ViewProtocolProbe, index int, entry u64, value u64, result u64) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0])
		assert C.dup2(fds[1], 2) == 2
		C.close(fds[1])
		input := [value, value, value, value, value, value, value, value, value, value, result,
			value, value]!
		mut output := [6]u64{}
		probe(unsafe { &input[0] }, entry, unsafe { &output[0] })
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
	for i, diagnostic in view_protocol_diagnostics() {
		assert output.contains(diagnostic) == (i == index), output
	}
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault']! {
		assert !output.contains(bad), output
	}
}

fn view_protocol_terminal_cases(entries [3]u64, probe ViewProtocolProbe, guard u64, shared u64, page usize) {
	for i, entry in entries {
		for value in [u64(0), 1, ~u64(0), guard]! {
			view_protocol_terminal(probe, i, entry, value, guard)
		}
		assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(shared), 0xa5, page)
		for writable in [true, false]! {
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | if writable {
				C.PROT_WRITE
			} else {
				0
			}) == 0
			for result in [shared, shared + u64(page) - 128]! {
				view_protocol_terminal(probe, i, entry, guard, result)
				for j in u64(0) .. u64(page) {
					assert unsafe { *(&u8(shared + j)) } == 0xa5
				}
			}
		}
	}
}

__global view_protocol_teardown_calls = 0

fn view_protocol_teardown(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	descriptor := view_protocol_resolve()
	view_protocol_graph(descriptor, false)
	view_protocol_shared(descriptor, view_protocol_opacity(), view_protocol_never())
	view_protocol_teardown_calls++
}

fn test_swiftui_view_protocol() {
	view_protocol_rejected()
	$if macos {
		handle := C.dlopen(view_protocol_library.str, C.RTLD_NOW)
		assert handle != unsafe { nil }
		descriptor := u64(C.dlsym(handle, c'$s7SwiftUI4ViewMp'))
		entries := view_protocol_graph(descriptor, true)
		for i, symbol in view_protocol_symbols() {
			name := symbol[1..]
			assert u64(C.dlsym(handle, name.str)) == descriptor + view_protocol_offsets()[i]
		}
		for i, symbol in view_protocol_defaults() {
			name := symbol[1..]
			assert C.dlsym(handle, name.str) == unsafe { nil }
			extension := name.replace('4ViewP', '4ViewPAAE')
			assert C.dlsym(handle, extension.str) != unsafe { nil }
			assert u64(C.dlsym(handle, extension.str)) != entries[i]
		}
		opacity := u64(C.dlsym(handle, c'$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP'))
		never := u64(C.dlsym(handle, c'$ss5NeverO7SwiftUI4ViewACWP'))
		assert opacity != 0 && never != 0
		view_protocol_shared(descriptor, opacity, never)
		for name in [c'$s7SwiftUI14_OpacityEffectVMn', c'$s7SwiftUI4TextVMn',
			c'$s7SwiftUI12ViewModifierMp']! {
			nominal := u64(C.dlsym(handle, name))
			assert nominal != 0 && view_protocol_relative(nominal + 4) == view_protocol_relative(descriptor + 4)
		}
		assert C.dlclose(handle) == 0
		println('NATIVE-SWIFTUI-VIEW-PROTOCOL: exact Body: View signature, six requirements, eight declaration aliases and three distinct private default callbacks, canonical View shared with Never and opacity, and native SwiftUI module identity; native graph callbacks and application code were not executed')
	}
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	shared_base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1) && shared_base != u64(-1)
	shared := shared_base + u64(page)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f1, 0xaa0103f0, 0xaa0203f3,
		0xd10043ff, 0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xa9442a29, 0xa9002be9, 0xf9402a28,
		0xf9402e34, 0xf9403235, 0xd63f0200, 0xa9000660, 0xa9010e62, 0xa9025674, 0x910043ff, 0xa9425bf5,
		0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ViewProtocolProbe(voidptr(code)) }
	for cycle in 0 .. 2 {
		objc_start()
		view_protocol_empty()
		for symbol in view_protocol_symbols() {
			for wrong in [symbol + 'Extra', symbol[1..], symbol.replace('7SwiftUI', '11SwiftUICore')]! {
				assert swiftui_view_protocol_symbol(wrong) == none
			}
			for library in ['/usr/lib/swift/libswiftCore.dylib',
				'/System/Library/Frameworks/Foundation.framework/Foundation',
				'/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! {
				assert runtime_symbol(library, symbol) == none
			}
		}
		for symbol in view_protocol_defaults() {
			assert swiftui_view_protocol_symbol(symbol + 'Extra') == none
			assert swiftui_view_protocol_symbol(symbol) == none
			assert runtime_symbol(view_protocol_library, symbol) == none
			for library in ['/usr/lib/swift/libswiftCore.dylib',
				'/System/Library/Frameworks/Foundation.framework/Foundation',
				'/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! {
				assert runtime_symbol(library, symbol) == none
			}
		}
		for symbol in ['_$s7SwiftUI4ViewP4BodyQa', '_$s7SwiftUI4ViewP4body4BodyQzvg',
			'_$s7SwiftUI4ViewP4body4BodyQzvgTj', '_$s7SwiftUI12ViewModifierMp']! {
			assert swiftui_view_protocol_symbol(symbol) == none
		}
		view_protocol_empty()
		ios_runtime.swiftui_opacity_retired = true
		view_protocol_rejected()
		view_protocol_empty()
		ios_runtime.swiftui_opacity_retired = false
		ios_runtime.swift_concurrency_retired = true
		view_protocol_rejected()
		view_protocol_empty()
		ios_runtime.swift_concurrency_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn view_protocol_reader((i + cycle) % 5) }
		resolved := workers.wait()
		for candidate in resolved {
			assert candidate != 0 && candidate == resolved[0]
		}
		descriptor := resolved[0]
		base := ios_runtime.swiftui_opacity_arena
		data := base + u64(page)
		assert base != 0 && descriptor == data + 640
		assert view_protocol_relative(descriptor + 4) == data + 192
		assert view_protocol_relative(descriptor + 28) == data + 832
		view_protocol_permissions(base, u64(page), true, false)
		view_protocol_permissions(data, u64(page), false, false)
		entries := view_protocol_graph(descriptor, false)
		for i, symbol in view_protocol_defaults() {
			assert entries[i] == base + 224 + u64(i * 16)
			assert swiftui_view_protocol_symbol(symbol) == none
			assert runtime_symbol(view_protocol_library, symbol) == none
			extension := symbol.replace('4ViewP', '4ViewPAAE')
			assert runtime_symbol(view_protocol_library, extension) or { panic(err) } != entries[i]
		}
		view_protocol_shared(descriptor, view_protocol_opacity(), view_protocol_never())
		view_protocol_terminal_cases(entries, probe, guard, shared, page)
		ios_runtime.swiftui_opacity_retired = true
		view_protocol_rejected()
		assert ios_runtime.swiftui_opacity_arena == base
		ios_runtime.swiftui_opacity_retired = false
		ios_runtime.swift_concurrency_retired = true
		assert view_protocol_resolve() == descriptor
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swiftui_modified_arena == 0 && ios_runtime.swiftui_text_view_arena == 0
		assert ios_runtime.swiftui_environment_transform_arena == 0 && ios_runtime.swift_heap.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixViewProtocolTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(view_protocol_teardown) }), c'v16@0:8')
		objc_register_class(cls)
		objc_autorelease(objc_new(cls))
		before := view_protocol_teardown_calls
		ios_runtime.swift_concurrency_retired = true
		objc_stop()
		assert view_protocol_teardown_calls == before + 1 && ios_runtime.swiftui_opacity_retired
		view_protocol_empty()
		view_protocol_unmapped(base, page)
		view_protocol_unmapped(data, page)
		view_protocol_rejected()
		view_protocol_empty()
		unsafe {
			resolved.free()
			workers.free()
		}
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	assert C.munmap(voidptr(shared_base), page * 3) == 0
	println('IOS-SWIFTUI-VIEW-PROTOCOL: eight declaration aliases and three private diagnostic defaults in the existing sealed opacity arena, canonical Never/opacity View and Body signature, eight cold readers in five resolution orders, 48 terminal child probes with protected inputs/Self/x8 and unchanged result pages at both guard boundaries, allocation-free rejected lookups, cached teardown access and two drained/unmapped lifetimes; SwiftUI graph construction and rendering remain unsupported')
}
