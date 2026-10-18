// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import time

#include <unistd.h>
#include <sys/wait.h>

fn C.fork() i32

type TlaRegister = fn (ImageDestructor, voidptr)
type TlaThunk = fn (voidptr) voidptr

struct TlaCase {
mut:
	id      u64
	mode    int
	first   u64
	second  u64
	events  [3]int
	used    int
	repeats int
}

__global tla_cases = unsafe { &TlaCase(nil) }
__global tla_ready = i64(0)
__global tla_go = i64(0)
__global tla_nils = i64(0)
__global tla_exec_used = 0
__global tla_exec_order = [8]int{}
__global tla_exec_phase = 0
__global tla_exec_first = u64(0)
__global tla_exec_bss = u64(0)

fn tla_api() TlaRegister {
	return unsafe { TlaRegister(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '__tlv_atexit') or { panic(err) })) }
}

fn tla_wait(slot &i64, value i64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_ref_change(slot, 0) != value {
		assert time.sys_mono_now() < deadline
		time.sleep(time.millisecond)
	}
}

fn tla_templates() {
	image_runtime_start(macho.Image{}, macho.Layout{}, 0)
	first := &ImageTls{ template: []u8{len: 32} }
	second := &ImageTls{ template: []u8{len: 32} }
	unsafe {
		*(&u32(first.template.data)) = 0x12345678
		*(&u32(second.template.data)) = 0xabcdef01
	}
	image_runtime.tls_modules << first
	image_runtime.tls_modules << second
	image_runtime.tls_descriptors[0x101] = TlsDescriptor{first, 0}
	image_runtime.tls_descriptors[0x108] = TlsDescriptor{first, 8}
	image_runtime.tls_descriptors[0x202] = TlsDescriptor{second, 0}
}

fn tla_case() &TlaCase {
	id := read64(image_tls_address(0x101))
	assert id < 16
	return unsafe { &TlaCase(u64(tla_cases) + id * sizeof(TlaCase)) }
}

fn tla_record(kind int, argument voidptr) {
	mut state := tla_case()
	assert image_tls_address(0x101) == state.first && image_tls_address(0x108) == state.first + 8
	assert image_tls_address(0x202) == state.second
	assert read64(state.second) == 0xfeed0000 + state.id && read64(state.first + 8) == 0xface0000 + state.id
	assert u64(argument) == if kind == 2 { state.second } else { state.first }
	assert state.used < state.events.len
	state.events[state.used] = kind
	state.used++
}

fn tla_a(argument voidptr) { tla_record(1, argument) }

fn tla_c(argument voidptr) { tla_record(3, argument) }

fn tla_b(argument voidptr) {
	tla_record(2, argument)
	tla_api()(tla_c, unsafe { voidptr(image_tls_address(0x101)) })
}

fn tla_repeat(argument voidptr) {
	mut state := tla_case()
	assert u64(argument) == state.first && read64(state.second) == 0xfeed0000 + state.id
	state.repeats++
	if state.repeats < 96 { tla_api()(tla_repeat, argument) }
}

fn tla_nil(argument voidptr) {
	assert argument == unsafe { nil }
	C.ios_ref_change(unsafe { &tla_nils }, 1)
}

fn tla_fill(mut state TlaCase) {
	state.first = image_tls_address(0x101)
	state.second = image_tls_address(0x202)
	assert read32(state.first) == 0x12345678 && read32(state.second) == 0xabcdef01
	for i in 16 .. 32 {
		assert unsafe { *(&u8(state.first + u64(i))) } == 0
		assert unsafe { *(&u8(state.second + u64(i))) } == 0
	}
	unsafe {
		*(&u64(state.first)) = state.id
		*(&u64(state.first + 8)) = 0xface0000 + state.id
		*(&u64(state.second)) = 0xfeed0000 + state.id
	}
}

fn tla_worker(argument voidptr) voidptr {
	mut state := unsafe { &TlaCase(argument) }
	tla_fill(mut state)
	darwin_set_errno(42)
	tla_api()(tla_a, unsafe { voidptr(state.first) })
	tla_api()(tla_b, unsafe { voidptr(state.second) })
	if state.mode == 3 { tla_api()(tla_repeat, unsafe { voidptr(state.first) }) }
	tla_api()(tla_nil, unsafe { nil })
	assert unsafe { *C.ios_errno_address() } == 42
	C.ios_ref_change(unsafe { &tla_ready }, 1)
	tla_wait(unsafe { &tla_go }, 1)
	if state.mode == 1 { darwin_pthread_exit(argument) }
	if state.mode == 2 { C.pthread_exit(argument) }
	return argument
}

fn tla_threads() {
	for _ in 0 .. 2 {
		tla_templates()
		tla_ready = 0
		tla_go = 0
		tla_nils = 0
		mut cases := [16]TlaCase{}
		tla_cases = unsafe { &cases[0] }
		mut threads := [16]u64{}
		for i in 0 .. 16 {
			cases[i].id = u64(i)
			cases[i].mode = i % 4
			assert C.pthread_create(unsafe { voidptr(&threads[i]) }, unsafe { nil }, unsafe { voidptr(tla_worker) }, unsafe { &cases[i] }) == 0
		}
		tla_wait(unsafe { &tla_ready }, 16)
		image_tls_lock.lock()
		assert image_runtime.tls_threads == 16
		image_tls_lock.unlock()
		for i in 0 .. 16 {
			for j in i + 1 .. 16 {
				assert cases[i].first != cases[j].first && cases[i].second != cases[j].second
			}
		}
		C.ios_ref_change(unsafe { &tla_go }, 1)
		for i in 0 .. 16 {
			mut returned := unsafe { voidptr(nil) }
			assert C.pthread_join(unsafe { voidptr(threads[i]) }, &returned) == 0 && returned == unsafe { &cases[i] }
			assert cases[i].events == [2, 3, 1]! && cases[i].used == 3
			assert cases[i].repeats == if cases[i].mode == 3 { 96 } else { 0 }
		}
		assert image_runtime.tls_threads == 0 && image_runtime.tls_owners == unsafe { nil } && tla_nils == 16
		cases[0] = TlaCase{}
		tla_fill(mut cases[0])
		tla_api()(tla_a, unsafe { voidptr(cases[0].first) })
		tla_api()(tla_b, unsafe { voidptr(cases[0].second) })
		image_tls_finalize_current()
		image_tls_finalize_current()
		assert cases[0].events == [2, 3, 1]! && image_runtime.tls_threads == 1
		assert image_tls_address(0x101) == cases[0].first
		image_runtime_stop()
		assert image_runtime == unsafe { nil }
		tla_cases = unsafe { nil }
	}
}

fn tla_fork() {
	tla_templates()
	image_atfork_start() or { panic(err) }
	mut cases := [16]TlaCase{}
	tla_cases = unsafe { &cases[0] }
	tla_fill(mut cases[0])
	tla_api()(tla_a, unsafe { voidptr(cases[0].first) })
	tla_ready = 0
	tla_go = 0
	cases[1].id = 1
	mut handle := u64(0)
	assert C.pthread_create(unsafe { voidptr(&handle) }, unsafe { nil }, unsafe { voidptr(tla_worker) }, unsafe { &cases[1] }) == 0
	tla_wait(unsafe { &tla_ready }, 1)
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		assert image_runtime.tls_threads == 1 && image_runtime.tls_owners != unsafe { nil }
		assert image_runtime.tls_owners.previous == unsafe { nil } && image_runtime.tls_owners.next == unsafe { nil }
		assert image_tls_address(0x101) == cases[0].first && cases[1].used == 0
		image_tls_finalize_current()
		assert cases[0].used == 1 && cases[1].used == 0
		image_runtime_stop()
		C._exit(0)
	}
	mut status := i32(-1)
	assert C.ios_waitpid(pid, &status, 0) == pid && status == 0
	assert image_runtime.tls_threads == 2 && cases[0].used == 0
	C.ios_ref_change(unsafe { &tla_go }, 1)
	assert C.pthread_join(unsafe { voidptr(handle) }, unsafe { nil }) == 0
	assert cases[1].events == [2, 3, 1]!
	image_tls_finalize_current()
	assert cases[0].used == 1
	image_runtime_stop()
	tla_cases = unsafe { nil }
}

fn tla_emit(tag u8) {
	mut value := tag
	assert C.write(1, unsafe { &value }, 1) == 1
}

fn tla_end_a(_ voidptr) { tla_emit(`A`) }

fn tla_end_c(_ voidptr) { tla_emit(`C`) }

fn tla_end_b(_ voidptr) {
	tla_emit(`B`)
	tla_api()(tla_end_c, unsafe { nil })
}

fn tla_global_a() { tla_emit(`1`) }

fn tla_global_b() {
	tla_emit(`2`)
	tla_api()(tla_end_c, unsafe { nil })
}

fn tla_child(mode string) {
	tla_templates()
	if mode in ['active', 'boundary']! {
		mut state := TlaCase{}
		tla_cases = unsafe { &state }
		tla_ready = 0
		tla_go = 0
		mut handle := u64(0)
		assert C.pthread_create(unsafe { voidptr(&handle) }, unsafe { nil }, unsafe { voidptr(tla_worker) }, unsafe { &state }) == 0
		tla_wait(unsafe { &tla_ready }, 1)
		if mode == 'boundary' {
			image_tls_require_current()
			assert false
		}
		image_runtime_stop()
		assert false
	} else if mode == 'pending' {
		tla_api()(tla_end_a, unsafe { nil })
		image_runtime_stop()
		assert false
	} else {
		assert image_atexit(tla_global_a) == 0 && image_atexit(tla_global_b) == 0
		tla_api()(tla_end_a, unsafe { nil })
		tla_api()(tla_end_b, unsafe { nil })
		if mode == 'immediate' { image_immediate_exit(0) }
		image_exit(0)
	}
}

fn tla_children() {
	for mode in ['exit', 'immediate', 'active', 'boundary', 'pending']! {
		mut p := os.new_process(os.executable())
		p.set_redirect_stdio_merged()
		mut env := os.environ()
		env['VINIX_TLV_CHILD'] = mode
		p.set_environment(env)
		p.run()
		log := p.stdout_slurp()
		p.wait()
		code := p.code
		p.close()
		if mode == 'exit' {
			assert code == 0 && log == 'BCA21', log
		} else if mode == 'immediate' {
			assert code == 0 && log == '', log
		} else if mode in ['active', 'boundary']! {
			assert code != 0 && log.contains('active thread-local owner at image shutdown'), log
		} else {
			assert code != 0 && log.contains('thread-local destructors remain after application finalization') && !log.starts_with('A'), log
		}
	}
}

fn tla_exec_record(value int) {
	assert tla_exec_used < tla_exec_order.len
	tla_exec_order[tla_exec_used] = value
	tla_exec_used++
	assert read32(tla_exec_first) == 0x12345678 && read32(tla_exec_bss) == 0xaabbccdd
	object := objc_allocate(ios_runtime.names['NSObject'])
	assert object != 0
	objc_release(object)
}

fn tla_exec_a(argument voidptr) {
	assert u64(argument) == tla_exec_first && tla_exec_phase == 2
	tla_exec_record(1)
}

fn tla_exec_c(argument voidptr) {
	assert u64(argument) == tla_exec_bss && tla_exec_phase == 2
	tla_exec_record(3)
}

fn tla_exec_b(argument voidptr) {
	assert u64(argument) == tla_exec_first && tla_exec_phase == 2
	tla_exec_record(2)
	tla_api()(tla_exec_c, unsafe { voidptr(tla_exec_bss) })
}

fn tla_exec_late(_ voidptr) {
	assert tla_exec_phase == 3
	tla_exec_record(5)
}

fn tla_exec_last(_ voidptr) {
	assert tla_exec_phase == 3
	tla_exec_record(7)
}

fn tla_exec_global() {
	assert tla_exec_phase == 2
	tla_exec_record(4)
	tla_exec_phase = 3
	tla_api()(tla_exec_late, unsafe { nil })
}

fn tla_exec_remove(header voidptr, slide i64) {
	assert tla_exec_phase == 3 && darwin_dyld_get_image_header(0) == header && darwin_dyld_get_image_vmaddr_slide(0) == slide
	tla_exec_record(6)
	tla_api()(tla_exec_last, unsafe { nil })
}

fn tla_exec_init(_ int, _ &&char, _ &&char, _ &&char) {
	assert tla_exec_phase == 0
	descriptor := u64(darwin_dyld_get_image_header(0)) + u64(C.getpagesize()) * 2 + 32
	thunk := unsafe { TlaThunk(voidptr(read64(descriptor))) }
	tla_exec_first = u64(thunk(unsafe { voidptr(descriptor) }))
	tla_exec_bss = u64(thunk(unsafe { voidptr(descriptor + 24) }))
	assert read32(tla_exec_first) == 0x12345678 && read64(tla_exec_bss) == 0
	unsafe { *(&u32(tla_exec_bss)) = 0xaabbccdd }
	tla_api()(tla_exec_a, unsafe { voidptr(tla_exec_first) })
	tla_api()(tla_exec_b, unsafe { voidptr(tla_exec_first) })
	assert image_atexit(tla_exec_global) == 0
	darwin_dyld_register_func_for_remove_image(tla_exec_remove)
	tla_exec_phase = 1
}

fn tla_exec_main(_ int, _ &&char, _ &&char, _ &&char) int {
	assert tla_exec_phase == 1
	tla_exec_phase = 2
	return 37
}

fn tla_put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn tla_put64(mut bytes []u8, at int, value u64) {
	for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn tla_text(mut bytes []u8, at int, value string) {
	for i, c in value { bytes[at + i] = c }
}

fn tla_segment(mut bytes []u8, at int, name string, address u64, size u64, fileoff u64, filesize u64, prot u32, sections u32) int {
	tla_put32(mut bytes, at, 0x19)
	tla_put32(mut bytes, at + 4, 72 + sections * 80)
	tla_text(mut bytes, at + 8, name)
	tla_put64(mut bytes, at + 24, address)
	tla_put64(mut bytes, at + 32, size)
	tla_put64(mut bytes, at + 40, fileoff)
	tla_put64(mut bytes, at + 48, filesize)
	tla_put32(mut bytes, at + 56, prot)
	tla_put32(mut bytes, at + 60, prot)
	tla_put32(mut bytes, at + 64, sections)
	return at + 72
}

fn tla_image() macho.Image {
	page := u64(C.getpagesize())
	preferred := u64(0x100000000)
	data := preferred + page * 2
	mut bytes := []u8{len: int(page * 3)}
	defer { unsafe { bytes.free() } }
	tla_put32(mut bytes, 0, 0xfeedfacf)
	tla_put32(mut bytes, 4, 0x100000c)
	tla_put32(mut bytes, 12, 2)
	tla_put32(mut bytes, 16, 6)
	tla_put32(mut bytes, 24, 0xa00085)
	mut at := tla_segment(mut bytes, 32, '__PAGEZERO', 0, preferred, 0, 0, 0, 0)
	at = tla_segment(mut bytes, at, '__TEXT', preferred, page, 0, page, 5, 0)
	at = tla_segment(mut bytes, at, '__DATA', data, page, page * 2, page, 3, 3)
	for i, name in ['__thread_data', '__thread_bss', '__thread_vars']! {
		offset := u64(if i == 0 {
			0
		} else if i == 1 {
			16
		} else {
			32
		})
		tla_text(mut bytes, at, name)
		tla_text(mut bytes, at + 16, '__DATA')
		tla_put64(mut bytes, at + 32, data + offset)
		tla_put64(mut bytes, at + 40, if i == 2 { u64(48) } else { u64(16) })
		tla_put32(mut bytes, at + 48, u32(page * 2 + offset))
		tla_put32(mut bytes, at + 52, 3)
		tla_put32(mut bytes, at + 64, u32(if i == 0 {
			0x11
		} else if i == 1 {
			0x12
		} else {
			0x13
		}))
		at += 80
	}
	tla_put32(mut bytes, at, 0x32)
	tla_put32(mut bytes, at + 4, 24)
	tla_put32(mut bytes, at + 8, 2)
	tla_put32(mut bytes, at + 12, 0x110000)
	tla_put32(mut bytes, at + 16, 0x110000)
	at += 24
	tla_put32(mut bytes, at, 0x80000028)
	tla_put32(mut bytes, at + 4, 24)
	tla_put64(mut bytes, at + 8, 1024)
	at += 24
	tla_put32(mut bytes, at, 0x1a)
	tla_put32(mut bytes, at + 4, 72)
	tla_put64(mut bytes, at + 8, preferred + 1040)
	at += 72
	tla_put32(mut bytes, 20, u32(at - 32))
	for i, address in [u64(unsafe { voidptr(tla_exec_main) }), u64(unsafe { voidptr(tla_exec_init) })]! {
		tla_put32(mut bytes, 1024 + i * 16, 0x58000050)
		tla_put32(mut bytes, 1028 + i * 16, 0xd61f0200)
		tla_put64(mut bytes, 1032 + i * 16, address)
	}
	tla_put32(mut bytes, int(page * 2), 0x12345678)
	for i in 0 .. 2 {
		tla_put64(mut bytes, int(page * 2) + 32 + i * 24, u64(unsafe { voidptr(C.ios_tlv_get_addr) }))
		tla_put64(mut bytes, int(page * 2) + 48 + i * 24, u64(i * 16))
	}
	return macho.parse(bytes) or { panic(err) }
}

fn tla_execution() {
	image := tla_image()
	for _ in 0 .. 2 {
		tla_exec_phase = 0
		tla_exec_used = 0
		tla_exec_order = [8]int{}
		result := execute(image, [os.executable()]) or { panic(err) }
		assert result == 37 && tla_exec_phase == 3 && tla_exec_used == 7
		for i, value in [2, 3, 1, 4, 5, 6, 7]! {
			assert tla_exec_order[i] == value
		}
		assert image_runtime == unsafe { nil } && module_runtime == unsafe { nil } && ios_runtime.live == 0
	}
	module_image_free(image)
}

fn test_tlv_atexit() {
	mode := os.getenv('VINIX_TLV_CHILD')
	if mode != '' {
		tla_child(mode)
		return
	}
	assert runtime_symbol('/usr/lib/libSystem.B.dylib', '__tlv_atexit') or { panic(err) } != 0
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
		'/System/Library/Frameworks/Foundation.framework/Foundation']! {
		if _ := runtime_symbol(library, '__tlv_atexit') {
			assert false
		}
	}
	tla_threads()
	tla_fork()
	tla_children()
	tla_execution()
	println('IOS-TLV-ATEXIT: scoped void callback/object ABI, 32 joined normal/pthread_exit owners with two TLS images, stable bytes through reentrant LIFO and 96 callbacks, nil arguments, fork ownership repair, native-matching process/immediate exit, active/pending shutdown rejection and two V Mach-O TLV constructor/main/destructor/removal executions')
}
