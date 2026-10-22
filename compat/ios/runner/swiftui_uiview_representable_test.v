// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

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

const representable_library = '/System/Library/Frameworks/SwiftUI.framework/SwiftUI'

type RepresentableProbe = fn (&u64, u64, &u64)

fn representable_symbols() [16]string {
	return ['_$s7SwiftUI19UIViewRepresentableMp', '_$s7SwiftUI19UIViewRepresentableTL',
		'_$s7SwiftUI19UIViewRepresentablePAA4ViewTb', '_$s10UIViewType7SwiftUI0A13RepresentablePTl',
		'_$s11Coordinator7SwiftUI19UIViewRepresentablePTl',
		'_$s7SwiftUI19UIViewRepresentableP04makeC07context0C4TypeQzAA0cD7ContextVyxG_tFTq',
		'_$s7SwiftUI19UIViewRepresentableP06updateC0_7contexty0C4TypeQz_AA0cD7ContextVyxGtFTq',
		'_$s7SwiftUI19UIViewRepresentableP06_resetC0_11coordinator7destroyy0C4TypeQz_11CoordinatorQzyyXEtFTq',
		'_$s7SwiftUI19UIViewRepresentableP09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZTq',
		'_$s7SwiftUI19UIViewRepresentableP15makeCoordinator0F0QzyFTq',
		'_$s7SwiftUI19UIViewRepresentableP19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tFTq',
		'_$s7SwiftUI19UIViewRepresentableP12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtFTq',
		'_$s7SwiftUI19UIViewRepresentableP21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztFTq',
		'_$s7SwiftUI19UIViewRepresentableP21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztFTq',
		'_$s7SwiftUI19UIViewRepresentableP24_modifyBridgedViewInputsyyAA01_gH0VzFZTq',
		'_$s7SwiftUI19UIViewRepresentableP14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZTq']!
}

fn representable_offsets() [16]u64 {
	return [u64(0), 52, 60, 68, 76, 84, 92, 100, 108, 116, 124, 132, 140, 148, 156, 164]!
}

fn representable_flags() [14]u32 {
	return [u32(0), 0xf0490007, 0x28a90007, 0x5f4b0011, 0x30cb0011, 0xf4060011, 0x18d40001, 0xdad40011,
		0x21320011, 0xeb0b0011, 0x4ec80011, 0x681f0011, 0x180f0001, 0xe0fc0001]!
}

fn representable_path(path u64, prefix string, expected u64) {
	for i in 0 .. prefix.len {
		assert unsafe { *(&u8(path + u64(i))) } == prefix[i]
	}
	marker := unsafe { *(&u8(path + u64(prefix.len))) }
	assert marker == 1 || marker == 2
	target := representable_relative(path + u64(prefix.len) + 1)
	assert (if marker == 2 { read64(target) } else { target }) == expected
	assert representable_text(path + u64(prefix.len) + 5) == 'Qz'
}

fn representable_graph(descriptor u64, view u64, never u64, native bool) [14]u64 {
	assert descriptor != 0 && descriptor & 3 == 0
	maps := representable_maps()
	defer { unsafe { maps.free() } }
	representable_permissions(descriptor, 172, false, native, maps)
	assert read32(descriptor) == 0x30043
	parent := representable_relative(descriptor + 4)
	assert read32(parent) == 0 && read32(parent + 4) == 0
	assert representable_text(representable_relative(parent + 8)) == 'SwiftUI'
	assert representable_text(representable_relative(descriptor + 8)) == 'UIViewRepresentable'
	assert read32(descriptor + 12) == 3 && read32(descriptor + 16) == 14
	assert representable_text(representable_relative(descriptor + 20)) == 'UIViewType Coordinator'
	assert read32(descriptor + 24) == 0x80
	assert representable_text(representable_relative(descriptor + 28)) == 'x'
	assert representable_indirect(descriptor + 32) == view
	assert read32(descriptor + 36) == 1
	representable_path(representable_relative(descriptor + 40), '4Body', view)
	never_path := representable_relative(descriptor + 44)
	marker := unsafe { *(&u8(never_path)) }
	assert marker == 1 || marker == 2
	never_target := representable_relative(never_path + 1)
	assert (if marker == 2 { read64(never_target) } else { never_target }) == never
	assert unsafe { *(&u8(never_path + 5)) } == 0
	assert read32(descriptor + 48) == 2
	representable_path(representable_relative(descriptor + 52), '10UIViewType', descriptor)
	assert representable_text(representable_relative(descriptor + 56)) == 'So6UIViewC'
	mut defaults := [14]u64{}
	for i, flags in representable_flags() {
		assert read32(descriptor + 60 + u64(i * 8)) == flags
		entry := representable_relative(descriptor + 64 + u64(i * 8))
		defaults[i] = entry
		if i == 0 || i == 1 || i == 3 || i == 4 || i == 7 {
			assert entry == 0
		} else if i == 2 {
			assert entry != 0 && representable_text(entry) == 'yt'
			assert unsafe { *(&u8(entry - 1)) } == 0xff
			representable_permissions(entry, 3, false, native, maps)
		} else {
			assert entry != 0
			representable_permissions(entry, 4, true, native, maps)
		}
	}
	assert defaults[6] == defaults[10] && defaults[6] == defaults[11] && defaults[6] == defaults[12]
	return defaults
}

fn representable_relative(field u64) u64 {
	mut bits := u32(0)
	for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(field + i)) }) << u32(i * 8) }
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn representable_indirect(field u64) u64 {
	bits := i32(read32(field))
	target := u64(i64(field) + i64(bits & ~1))
	return if bits & 1 != 0 { read64(target) } else { target }
}

fn representable_text(address u64) string {
	assert address != 0
	return unsafe { (&char(address)).vstring() }
}

fn representable_maps() string {
	$if macos {
		return ''
	} $else {
		return os.read_file('/proc/self/maps') or { panic(err) }
	}
}

// Scan the caller's owned snapshot without allocating line/field substrings.
fn representable_maps_permissions(maps string, address u64, bytes u64, executable bool) {
	mut cursor := 0
	for cursor < maps.len {
		start, after_start := representable_maps_hex(maps, cursor)
		cursor = after_start
		assert cursor < maps.len && maps[cursor] == `-`
		cursor++
		end, after_end := representable_maps_hex(maps, cursor)
		cursor = after_end
		assert cursor < maps.len && maps[cursor] == ` `
		for cursor < maps.len && maps[cursor] == ` ` { cursor++ }
		assert cursor + 4 <= maps.len
		if address >= start && address < end {
			assert bytes <= end - address
			assert maps[cursor] == `r` && maps[cursor + 1] == `-`
			assert maps[cursor + 2] == if executable { `x` } else { `-` }
			assert maps[cursor + 3] == `p`
			return
		}
		for cursor < maps.len && maps[cursor] != `\n` { cursor++ }
		if cursor < maps.len { cursor++ }
	}
	assert false, 'required SwiftUI mapping was absent'
}

fn representable_maps_hex(maps string, first int) (u64, int) {
	mut cursor := first
	mut value := u64(0)
	for cursor < maps.len {
		digit := match maps[cursor] {
			`0`...`9` { u64(maps[cursor] - `0`) }
			`a`...`f` { u64(maps[cursor] - `a` + 10) }
			`A`...`F` { u64(maps[cursor] - `A` + 10) }
			else { break }
		}
		assert cursor - first < 16
		value = value * 16 + digit
		cursor++
	}
	assert cursor > first
	return value, cursor
}

fn representable_permissions(address u64, bytes u64, executable bool, native bool, maps string) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [64]i32{}
		mut count := u32(C.VM_REGION_SUBMAP_INFO_COUNT_64)
		mut depth := u32(999)
		assert C.vm_region_recurse_64(C.mach_task_self(), &start, &size, &depth, unsafe { &info[0] }, &count) == 0
		assert start <= address && address + bytes <= start + size
		if native && !executable {
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
		}
	} $else {
		representable_maps_permissions(maps, address, bytes, executable)
	}
}

fn representable_resolve() u64 {
	return runtime_symbol(representable_library, '_$s7SwiftUI19UIViewRepresentableMp') or { panic(err) }
}

fn representable_empty() {
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

fn representable_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(voidptr(address), page, &residency) == -1
	}
}

// Capture x0-x7/x8/x20/x21/d0/d1; supply protected x9/x10 and stack arguments
// too. The thunk must preserve Swift self and context across its tail branch.
fn representable_probe_code(page usize) u64 {
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	ops := [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f1, 0xaa0103f0, 0xaa0203f3, 0xd10043ff,
		0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xa9442a29, 0xa9002be9, 0xf9402a28, 0xf9402e34,
		0xf9403235, 0xfd403620, 0xfd403a21, 0xd63f0200, 0xa9000660, 0xa9010e62, 0xa9021664, 0xa9031e66,
		0xf9002268, 0xa904d674, 0x6d058660, 0x910043ff, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]!
	for i, op in ops { write32(code + u64(i * 4), op) }
	// A closure records its Swift context and increments a counter synchronously.
	for i, op in [u32(0xf9400289), 0x91000529, 0xf9000289, 0xf9000694, 0xd2824680, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 152))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	return code
}

fn representable_inputs(value u64, result u64) [15]u64 {
	return [value, value, value, value, value, value, value, value, value, value, result, value,
		value, u64(0x7ff800000000abcd), u64(0x8000000000000000)]!
}

// kind: 0 empty default, 1 nil Optional<CGSize>, 2 indirect LayoutOptions.
fn representable_success(probe RepresentableProbe, entry u64, kind int, value u64, result u64) {
	input := representable_inputs(value, result)
	mut output := [15]u64{}
	output[0] = 0xcafe
	output[14] = 0xbeef
	probe(unsafe { &input[0] }, entry, unsafe { &output[1] })
	assert output[0] == 0xcafe && output[14] == 0xbeef
	assert output[10] == value && output[11] == value // Swift self/context.
	if kind == 1 {
		assert output[1] == 0 && output[2] == 0 && output[3] == 1
		for i in 3 .. 8 {
			assert output[i + 1] == input[i]
		}
		assert output[9] == result && output[12] == input[13] && output[13] == input[14]
	} else if kind == 2 {
		assert read64(result) == 1
		for i in 0 .. 8 {
			assert output[i + 1] == input[i]
		}
		assert output[9] == result && output[12] == input[13] && output[13] == input[14]
	}
}

fn representable_terminal(probe RepresentableProbe, entry u64, value u64, result u64, diagnostic string) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0])
		assert C.dup2(fds[1], 2) == 2
		C.close(fds[1])
		input := representable_inputs(value, result)
		mut output := [13]u64{}
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
	assert output.contains(diagnostic), output
	for bad in ['runtime error:', 'AddressSanitizer', 'SIGSEGV', 'SIGBUS', 'Segmentation fault']! {
		assert !output.contains(bad), output
	}
}

fn representable_page_unchanged(data u64, page usize, written u64, bytes u64) {
	for i in u64(0) .. u64(page) {
		if written != 0 && data + i >= written && data + i < written + bytes { continue }
		assert unsafe { *(&u8(data + i)) } == 0xa5
	}
}

fn representable_reset(probe RepresentableProbe, entry u64, destroy u64, guard u64, shared u64, page usize) {
	assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0
	for context in [shared, shared + u64(page) - 16]! {
		for value in [u64(0), 1, ~u64(0), guard]! {
			C.memset(voidptr(shared), 0xa5, page)
			unsafe {
				*(&u64(context)) = 41
				*(&u64(context + 8)) = 0
			}
			mut input := representable_inputs(value, guard)
			input[2] = destroy
			input[3] = context
			input[11] = guard
			input[12] = ~u64(0)
			mut output := [15]u64{}
			output[0] = 0xcafe
			output[14] = 0xbeef
			probe(unsafe { &input[0] }, entry, unsafe { &output[1] })
			assert output[0] == 0xcafe && output[14] == 0xbeef
			assert output[10] == guard && output[11] == ~u64(0)
			assert read64(context) == 42 && read64(context + 8) == context
			representable_page_unchanged(shared, page, context, 16)
		}
	}
}

fn representable_default_cases(entries [14]u64, probe RepresentableProbe, destroy u64, guard u64, shared u64, page usize) {
	representable_reset(probe, entries[5], destroy, guard, shared, page)
	for i in [6, 9, 10, 11, 12]! {
		for value in [u64(0), 1, ~u64(0), guard]! {
			representable_success(probe, entries[i], if i == 9 { 1 } else { 0 }, value, guard)
		}
	}
	for value in [u64(0), 1, ~u64(0), guard]! {
		representable_terminal(probe, entries[8], value, guard, 'iOS: SwiftUI UIViewRepresentable identified-view tree result is not implemented')
	}
	for writable in [true, false]! {
		for result in [shared, shared + u64(page) - 8]! {
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0
			C.memset(voidptr(shared), 0xa5, page)
			assert C.mprotect(voidptr(shared), page, C.PROT_READ | if writable {
				C.PROT_WRITE
			} else {
				0
			}) == 0
			for i in [6, 9, 10, 11, 12]! {
				representable_success(probe, entries[i], if i == 9 { 1 } else { 0 }, guard, result)
			}
			representable_terminal(probe, entries[8], guard, result, 'iOS: SwiftUI UIViewRepresentable identified-view tree result is not implemented')
			representable_page_unchanged(shared, page, 0, 0)
		}
	}
	assert C.mprotect(voidptr(shared), page, C.PROT_READ | C.PROT_WRITE) == 0
	for result in [shared, shared + u64(page) - 8]! {
		for value in [u64(0), 1, ~u64(0), guard]! {
			C.memset(voidptr(shared), 0xa5, page)
			representable_success(probe, entries[13], 2, value, result)
			representable_page_unchanged(shared, page, result, 8)
		}
	}
}

fn representable_canonical(view u64, never_table u64, opacity_table u64) u64 {
	assert view != 0 && never_table != 0 && opacity_table != 0
	conformance := read64(never_table)
	assert read32(conformance + 12) == 8 && representable_indirect(conformance) == view
	never := read64(representable_relative(conformance + 4))
	assert read32(never) == 0x52 && representable_text(representable_relative(never + 8)) == 'Never'
	assert representable_text(representable_relative(representable_relative(never + 4) + 8)) == 'Swift'
	modifier := representable_indirect(read64(opacity_table))
	assert representable_text(representable_relative(modifier + 8)) == 'ViewModifier'
	assert representable_indirect(modifier + 32) == view
	return never
}

fn representable_graph_runtime(descriptor u64) [14]u64 {
	view := runtime_symbol(representable_library, '_$s7SwiftUI4ViewMp') or { panic(err) }
	never := runtime_symbol(representable_library, '_$ss5NeverO7SwiftUI4ViewACWP') or { panic(err) }
	opacity := runtime_symbol(representable_library, '_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP') or { panic(err) }
	return representable_graph(descriptor, view, representable_canonical(view, never, opacity), false)
}

fn representable_private_name(index int) string {
	name := representable_symbols()[index + 2]
	return name[..name.len - 2]
}

fn representable_rejected() {
	for symbol in representable_symbols() {
		assert swiftui_uiview_representable_symbol(symbol) == none
	}
}

fn representable_reset_export_rejected() {
	// The private protocol default does not export the public extension method.
	symbol := representable_private_name(5).replace('19UIViewRepresentableP', '19UIViewRepresentablePAAE')
	assert swiftui_uiview_representable_symbol(symbol) == none
	assert runtime_symbol(representable_library, symbol) == none
}

fn representable_reader(first int) u64 {
	first_symbol := match first {
		1 { '_$s7SwiftUI4ViewMp' }
		2 { '_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP' }
		3 { '_$ss5NeverO7SwiftUI4ViewACWP' }
		4 { representable_symbols()[3] }
		5 {
			'_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ'
		}
		else { representable_symbols()[0] }
	}
	assert runtime_symbol(representable_library, first_symbol) or { panic(err) } != 0
	mut descriptor := u64(0)
	for _ in 0 .. 128 {
		descriptor = representable_resolve()
		for i, symbol in representable_symbols() {
			assert runtime_symbol(representable_library, symbol) or { panic(err) } == descriptor + representable_offsets()[i]
		}
		representable_graph_runtime(descriptor)
	}
	return descriptor
}

__global representable_teardown_calls = 0
__global representable_probe_address = u64(0)
__global representable_guard_address = u64(0)
__global representable_shared_address = u64(0)

fn representable_teardown(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	entries := representable_graph_runtime(representable_resolve())
	representable_reset(unsafe { RepresentableProbe(voidptr(representable_probe_address)) }, entries[5], representable_probe_address + 128,
		representable_guard_address, representable_shared_address, usize(C.getpagesize()))
	representable_teardown_calls++
}

fn test_swiftui_uiview_representable() {
	representable_rejected()
	$if macos {
		// This UIKit declaration exists in the Catalyst image. Host checks must be
		// linked as Catalyst; no native defaults or app instructions are invoked.
		handle := C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/SwiftUI', C.RTLD_NOW)
		assert handle != unsafe { nil }
		descriptor := u64(C.dlsym(handle, c'$s7SwiftUI19UIViewRepresentableMp'))
		view := u64(C.dlsym(handle, c'$s7SwiftUI4ViewMp'))
		never := u64(C.dlsym(handle, c'$ss5NeverO7SwiftUI4ViewACWP'))
		opacity := u64(C.dlsym(handle, c'$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP'))
		entries := representable_graph(descriptor, view, representable_canonical(view, never, opacity), true)
		for i, symbol in representable_symbols() {
			name := symbol[1..]
			assert u64(C.dlsym(handle, name.str)) == descriptor + representable_offsets()[i]
		}
		for i in [5, 6, 8, 9, 10, 11, 12, 13]! {
			private := representable_private_name(i)[1..]
			assert C.dlsym(handle, private.str) == unsafe { nil }
			extension := private.replace('19UIViewRepresentableP', '19UIViewRepresentablePAAE')
			public := u64(C.dlsym(handle, extension.str))
			assert public != 0 && public != entries[i]
		}
		assert C.dlclose(handle) == 0
		println('NATIVE-SWIFTUI-UIVIEW-REPRESENTABLE: Catalyst descriptor with three generic constraints, fourteen requirements and sixteen exact aliases; canonical View/Never/opacity references, Coordinator Void mangling, five absent defaults and eight private executable entries including four shared empty defaults; native defaults and application code were not executed')
	}
	page := usize(C.getpagesize())
	code := representable_probe_code(page)
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	shared_base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1) && shared_base != u64(-1)
	shared := shared_base + u64(page)
	probe := unsafe { RepresentableProbe(voidptr(code)) }
	representable_probe_address = code
	representable_guard_address = guard
	representable_shared_address = shared
	for cycle in 0 .. 2 {
		objc_start()
		representable_empty()
		for symbol in representable_symbols() {
			for wrong in [symbol + 'Extra', symbol[1..], symbol.replace('7SwiftUI', '11SwiftUICore')]! {
				assert swiftui_uiview_representable_symbol(wrong) == none
			}
			for library in ['/usr/lib/swift/libswiftCore.dylib',
				'/System/Library/Frameworks/Foundation.framework/Foundation',
				'/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! {
				assert runtime_symbol(library, symbol) == none
			}
		}
		for i in [5, 6, 8, 9, 10, 11, 12, 13]! {
			private := representable_private_name(i)
			assert swiftui_uiview_representable_symbol(private) == none
			assert runtime_symbol(representable_library, private) == none
		}
		for symbol in ['_$s7SwiftUI19NSViewRepresentableMp',
			'_$s7SwiftUI29UIViewControllerRepresentableMp',
			'_$s7SwiftUI19UIViewRepresentableP10UIViewTypeQa',
			'_$s7SwiftUI19UIViewRepresentableP11CoordinatorQa']! {
			assert swiftui_uiview_representable_symbol(symbol) == none
		}
		representable_reset_export_rejected()
		representable_empty()
		ios_runtime.swiftui_opacity_retired = true
		representable_rejected()
		representable_empty()
		ios_runtime.swiftui_opacity_retired = false
		ios_runtime.swift_concurrency_retired = true
		representable_rejected()
		representable_empty()
		ios_runtime.swift_concurrency_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn representable_reader((i + cycle) % 6) }
		resolved := workers.wait()
		for candidate in resolved {
			assert candidate != 0 && candidate == resolved[0]
		}
		descriptor := resolved[0]
		base := ios_runtime.swiftui_opacity_arena
		data := base + u64(page)
		assert base != 0 && descriptor == data + 1152
		assert representable_relative(descriptor + 4) == data + 192
		maps := representable_maps()
		representable_permissions(base, u64(page), true, false, maps)
		representable_permissions(data, u64(page), false, false, maps)
		unsafe { maps.free() }
		entries := representable_graph_runtime(descriptor)
		representable_reset_export_rejected()
		assert entries[2] == data + 1489
		for i, offset in [u64(0), 0, 0, 0, 0, 272, 288, 0, 304, 320, 288, 288, 288, 336]! {
			if offset == 0 { continue }
			assert entries[i] == base + offset
			if i == 5 { continue } // The public reset extension is outside this declaration increment.
			private := representable_private_name(i)
			extension := private.replace('19UIViewRepresentableP', '19UIViewRepresentablePAAE')
			assert runtime_symbol(representable_library, extension) or { panic(err) } != entries[i]
		}
		representable_default_cases(entries, probe, code + 128, guard, shared, page)
		ios_runtime.swiftui_opacity_retired = true
		representable_rejected()
		assert ios_runtime.swiftui_opacity_arena == base
		ios_runtime.swiftui_opacity_retired = false
		ios_runtime.swift_concurrency_retired = true
		assert representable_resolve() == descriptor
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixRepresentableTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(representable_teardown) }), c'v16@0:8')
		objc_register_class(cls)
		objc_autorelease(objc_new(cls))
		before := representable_teardown_calls
		ios_runtime.swift_concurrency_retired = true
		objc_stop()
		assert representable_teardown_calls == before + 1 && ios_runtime.swiftui_opacity_retired
		representable_empty()
		representable_unmapped(base, page)
		representable_unmapped(data, page)
		representable_rejected()
		representable_empty()
		unsafe {
			resolved.free()
			workers.free()
		}
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	assert C.munmap(voidptr(shared_base), page * 3) == 0
	println('IOS-SWIFTUI-UIVIEW-REPRESENTABLE: sixteen declaration aliases and fourteen native-matched requirements in the existing sealed opacity arena; canonical View/Body Never, UIView superclass and Coordinator Void signatures, eight readers in six resolution orders, synchronous reset destroy closure and restored Swift context, empty defaults/nil CGSize/exact eight-byte layout results with protected arguments and guard boundaries, sixteen terminal identified-tree child probes with unchanged writable/read-only result pages, rejected lookups without arena allocation, cached teardown access and two drained/unmapped lifetimes; UIKit view creation, graph construction and rendering remain unsupported')
}
