// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import time

type DcbRegister = fn (DyldImageCallback)

struct DcbEvent {
	kind   int
	header u64
	slide  i64
}

struct DcbMapping {
	image  macho.Image
	layout macho.Layout
	base   u64
}

__global dcb_events = [8192]DcbEvent{}
__global dcb_used = 0
__global dcb_nested = false
__global dcb_services = false
__global dcb_phase = 0
__global dcb_init_count = 0
__global dcb_main_count = 0
__global dcb_remove_count = 0
__global dcb_worker_check = false
__global dcb_ready = [2]i32{}
__global dcb_release = [2]i32{}
__global dcb_stop_state = u64(0)

fn dcb_add_api() DcbRegister {
	return unsafe { DcbRegister(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '__dyld_register_func_for_add_image') or { panic(err) })) }
}

fn dcb_remove_api() DcbRegister {
	return unsafe { DcbRegister(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '__dyld_register_func_for_remove_image') or { panic(err) })) }
}

fn dcb_objc_worker() {
	object := objc_allocate(ios_runtime.names['NSObject'])
	assert object != 0
	objc_release(object)
}

fn dcb_record(kind int, header voidptr, slide i64) {
	assert dcb_used < dcb_events.len && read32(u64(header)) == 0xfeedfacf
	mut found := false
	for i in u32(0) .. darwin_dyld_image_count() {
		if darwin_dyld_get_image_header(i) == header {
			assert darwin_dyld_get_image_vmaddr_slide(i) == slide
			found = true
		}
	}
	assert found
	mut info := DarwinDlInfo{}
	assert darwin_dladdr(u64(header), &info) == 1 && info.base == header
	mut size := u64(0)
	assert darwin_getsectiondata(u64(header), c'__DATA', c'__fixture', &size) != 0 && size == 64
	if dcb_services {
		assert image_runtime != unsafe { nil } && image_runtime.started
		assert read32(image_tls_address(0xdcb)) == 0x12345678
		dcb_objc_worker()
	}
	dcb_events[dcb_used] = DcbEvent{kind, u64(header), slide}
	dcb_used++
}

fn dcb_added_a(header voidptr, slide i64) {
	dcb_record(1, header, slide)
	if dcb_nested {
		dcb_nested = false
		dcb_add_api()(dcb_added_c)
	}
	if dcb_worker_check {
		dcb_worker_check = false
		worker := spawn dcb_objc_worker()
		worker.wait()
	}
}

fn dcb_added_b(header voidptr, slide i64) { dcb_record(2, header, slide) }

fn dcb_added_c(header voidptr, slide i64) { dcb_record(3, header, slide) }

fn dcb_removed_a(header voidptr, slide i64) {
	dcb_record(4, header, slide)
	assert module_runtime.dyld_retiring
	dyld_images_retire() // Reentrant retirement must not deliver twice.
}

fn dcb_removed_b(header voidptr, slide i64) { dcb_record(5, header, slide) }

fn dcb_registrar() {
	for _ in 0 .. 16 { dcb_add_api()(dcb_added_b) }
}

fn dcb_attach(region DcbMapping, path string) {
	index := module_runtime.modules.len
	module_runtime.modules << &LoadedModule{
		image:  region.image
		layout: region.layout
		base:   region.base
		path:   path.clone()
	}
	module_runtime.lookup_order << ModuleProvider{ index: index }
}

fn dcb_release_guards(regions []DcbMapping) {
	page := u64(C.getpagesize())
	module_image_free(regions[0].image)
	assert C.munmap(unsafe { voidptr(regions[0].base) }, usize(regions[0].layout.size)) == 0
	for region in regions {
		assert C.munmap(unsafe { voidptr(region.base - page) }, usize(page)) == 0
		assert C.munmap(unsafe { voidptr(region.base + region.layout.size) }, usize(page)) == 0
	}
}

fn dcb_inventory() {
	dcb_used = 0
	regions := [dcb_mapping(0x100000000, true, false), dcb_mapping(0, false, true),
		dcb_mapping(0x7000000000000000, false, false), dcb_mapping(0x300000000, false, false)]
	modules_start(regions[0].image, regions[0].layout, regions[0].base, '/main', false)
	for i in 1 .. 3 { dcb_attach(regions[i], '/library-' + i.str()) }
	module_runtime.order = [2, 0, 1]
	dcb_add_api()(dcb_added_a)
	dcb_remove_api()(dcb_removed_a)
	dcb_remove_api()(dcb_removed_b)
	dcb_remove_api()(dcb_removed_a)
	assert dcb_used == 0 // An unbound batch must not run application code.
	dyld_images_publish()
	assert dcb_used == 3
	for i in 0 .. 3 {
		assert dcb_events[i].kind == 1 && dcb_events[i].header == u64(darwin_dyld_get_image_header(u32(i)))
	}
	dyld_images_publish()
	assert dcb_used == 3
	dcb_add_api()(dcb_added_a)
	assert dcb_used == 6
	dcb_nested = true
	dcb_add_api()(dcb_added_a)
	assert dcb_used == 12
	for i, kind in [1, 3, 3, 3, 1, 1]! {
		assert dcb_events[6 + i].kind == kind
	}
	assert module_runtime.dyld_add == [u64(unsafe { voidptr(dcb_added_a) }),
		u64(unsafe { voidptr(dcb_added_a) }), u64(unsafe { voidptr(dcb_added_c) }),
		u64(unsafe { voidptr(dcb_added_a) })]
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn dcb_registrar() }
	workers.wait()
	unsafe { workers.free() }
	assert dcb_used == 12 + 8 * 16 * 3 && module_runtime.dyld_add.len == 132
	before := dcb_used
	dcb_attach(regions[3], '/fourth')
	module_runtime.order << 3
	dyld_images_publish()
	assert dcb_used == before + 132
	for i, kind in [1, 1, 3, 1]! {
		assert dcb_events[before + i].kind == kind
	}
	for i in 4 .. 132 {
		assert dcb_events[before + i].kind == 2
	}
	for i in before .. dcb_used {
		assert dcb_events[i].header == u64(darwin_dyld_get_image_header(3))
	}
	handle := darwin_dlopen(c'/fourth', 2)
	assert handle != 0 && darwin_dlclose(handle) == 0 && dcb_used == before + 132
	closing := dcb_used
	dyld_images_retire()
	assert dcb_used == closing + 12
	for i, index in [3, 1, 0, 2]! {
		for j, kind in [4, 5, 4]! {
			event := dcb_events[closing + i * 3 + j]
			assert event.kind == kind && event.header == u64(darwin_dyld_get_image_header(u32(index)))
		}
	}
	dyld_images_retire()
	dcb_add_api()(dcb_added_a)
	dcb_remove_api()(dcb_removed_a)
	assert dcb_used == closing + 12
	modules_stop()
	assert module_runtime == unsafe { nil }
	dcb_add_api()(dcb_added_a)
	dcb_remove_api()(dcb_removed_a)
	dcb_release_guards(regions)
	unsafe { regions.free() }
}

fn dcb_blocked(header voidptr, slide i64) {
	dcb_record(6, header, slide)
	if dcb_used == 1 {
		mut byte := u8(1)
		assert C.write(dcb_ready[1], unsafe { &byte }, 1) == 1
		assert C.read(dcb_release[0], unsafe { &byte }, 1) == 1
	}
}

fn dcb_blocking_registrar() { dcb_add_api()(dcb_blocked) }

fn dcb_stopper() {
	C.ios_store_pointer(unsafe { &dcb_stop_state }, 1)
	modules_stop()
	C.ios_store_pointer(unsafe { &dcb_stop_state }, 2)
}

fn dcb_drain() {
	dcb_used = 0
	dcb_stop_state = 0
	region := dcb_mapping(0x100000000, true, false)
	modules_start(region.image, region.layout, region.base, '/drain', false)
	dyld_images_publish()
	assert C.pipe(unsafe { &dcb_ready[0] }) == 0 && C.pipe(unsafe { &dcb_release[0] }) == 0
	worker := spawn dcb_blocking_registrar()
	mut byte := u8(0)
	assert C.read(dcb_ready[0], unsafe { &byte }, 1) == 1
	stopper := spawn dcb_stopper()
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_load_pointer(unsafe { &dcb_stop_state }) == 0 {
		assert time.sys_mono_now() < deadline
		time.sleep(time.millisecond)
	}
	assert C.ios_load_pointer(unsafe { &dcb_stop_state }) == 1
	assert read32(region.base) == 0xfeedfacf
	assert C.write(dcb_release[1], unsafe { &byte }, 1) == 1
	worker.wait()
	stopper.wait()
	assert module_runtime == unsafe { nil } && C.ios_load_pointer(unsafe { &dcb_stop_state }) == 2
	for fd in [dcb_ready[0], dcb_ready[1], dcb_release[0], dcb_release[1]]! {
		assert C.close(fd) == 0
	}
	dcb_release_guards([region])
}

fn dcb_execute_term() {
	assert dcb_phase == 2
	dcb_phase = 3
}

fn dcb_execute_remove(header voidptr, slide i64) {
	assert dcb_phase == 3
	dcb_record(7, header, slide)
	dcb_remove_count++
}

fn dcb_execute_init(_ int, _ &&char, _ &&char, _ &&char) {
	assert dcb_phase == 0 && darwin_dyld_image_count() == 1 && module_runtime.modules[0].dyld_published
	dcb_phase = 1
	dcb_init_count++
	mut tls := &ImageTls{ template: [u8(0x78), 0x56, 0x34, 0x12] }
	assert C.pthread_key_create(unsafe { voidptr(&tls.key) }, unsafe { voidptr(C.free) }) == 0
	tls.active = true
	image_runtime.tls_modules << tls
	image_runtime.tls_descriptors[0xdcb] = TlsDescriptor{tls, 0}
	dcb_services = true
	dcb_worker_check = true
	dcb_add_api()(dcb_added_a)
	dcb_remove_api()(dcb_execute_remove)
	assert image_atexit(dcb_execute_term) == 0
}

fn dcb_execute_main(_ int, _ &&char, _ &&char, _ &&char) int {
	assert dcb_phase == 1 && dcb_services
	dcb_phase = 2
	dcb_main_count++
	return 37
}

fn dcb_execution() {
	region := dcb_mapping(0x100000000, true, false)
	mut bytes := region.image.data.clone()
	at := 32 + int(read32(region.base + 20))
	dcb_put32(mut bytes, 16, read32(region.base + 16) + 1)
	dcb_put32(mut bytes, 20, u32(at + 72 - 32))
	dcb_put32(mut bytes, at, 0x1a) // LC_ROUTINES_64 executes the V test constructor.
	dcb_put32(mut bytes, at + 4, 72)
	dcb_put64(mut bytes, at + 8, 0x100000000 + 1040)
	for i, address in [u64(unsafe { voidptr(dcb_execute_main) }),
		u64(unsafe { voidptr(dcb_execute_init) })]! {
		dcb_put32(mut bytes, 1024 + i * 16, 0x58000050) // LDR x16, PC+8
		dcb_put32(mut bytes, 1028 + i * 16, 0xd61f0200) // BR x16
		dcb_put64(mut bytes, 1032 + i * 16, address)
	}
	image := macho.parse(bytes) or { panic(err) }
	for i in 0 .. 2 {
		dcb_phase = 0
		result := execute(image, [os.executable()]) or { panic(err) }
		assert result == 37
		dcb_services = false
		assert dcb_phase == 3 && dcb_init_count == i + 1 && dcb_main_count == i + 1 && dcb_remove_count == i + 1
		assert module_runtime == unsafe { nil } && image_runtime == unsafe { nil } && ios_runtime.live == 0
	}
	module_image_free(image)
	// A rejected initializer must neither publish an image nor call its code.
	dcb_put64(mut bytes, at + 8, 0x100000000 + u64(bytes.len) + 16)
	bad := macho.parse(bytes) or { panic(err) }
	if _ := execute(bad, [os.executable()]) {
		assert false
	} else {
		assert err.msg().contains('initializer is not executable')
	}
	assert dcb_init_count == 2 && dcb_main_count == 2 && dcb_remove_count == 2
	assert module_runtime == unsafe { nil } && image_runtime == unsafe { nil }
	module_image_free(bad)
	unsafe { bytes.free() }
	dcb_release_guards([region])
}

fn test_dyld_callbacks() {
	for symbol in ['__dyld_register_func_for_add_image', '__dyld_register_func_for_remove_image']! {
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', symbol) or { panic(err) } != 0
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation']! {
			if _ := runtime_symbol(library, symbol) {
				assert false
			}
		}
	}
	for _ in 0 .. 2 { dcb_inventory() }
	dcb_drain()
	dcb_execution()
	before := dcb_used
	modules_start(macho.Image{}, macho.Layout{}, 1, '/audit', true)
	dcb_add_api()(dcb_added_a)
	dcb_remove_api()(dcb_removed_a)
	dyld_images_publish()
	modules_stop()
	assert dcb_used == before
	println('IOS-DYLD-CALLBACKS: real headers/slides and section lookup, synchronous duplicate/nested replay, ordered batch publication, eight registrars, callback draining before unmap, two V Mach-O constructor/main/destructor runs with live Objective-C/TLS, failed binding and audit exclusion')
}

fn dcb_put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn dcb_put64(mut bytes []u8, at int, value u64) {
	for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn dcb_text(mut bytes []u8, at int, text string) {
	for i, c in text { bytes[at + i] = c }
}

fn dcb_segment(mut bytes []u8, at int, name string, address u64, size u64,
	fileoff u64, filesize u64, prot u32, section bool) int {
	length := if section { 152 } else { 72 }
	dcb_put32(mut bytes, at, 0x19)
	dcb_put32(mut bytes, at + 4, u32(length))
	dcb_text(mut bytes, at + 8, name)
	dcb_put64(mut bytes, at + 24, address)
	dcb_put64(mut bytes, at + 32, size)
	dcb_put64(mut bytes, at + 40, fileoff)
	dcb_put64(mut bytes, at + 48, filesize)
	dcb_put32(mut bytes, at + 56, prot)
	dcb_put32(mut bytes, at + 60, prot)
	if section {
		dcb_put32(mut bytes, at + 64, 1)
		dcb_text(mut bytes, at + 72, '__fixture')
		dcb_text(mut bytes, at + 88, name)
		dcb_put64(mut bytes, at + 104, address + 32)
		dcb_put64(mut bytes, at + 112, 64)
		dcb_put32(mut bytes, at + 120, u32(fileoff + 32))
		dcb_put32(mut bytes, at + 124, 3)
	}
	return at + length
}

// Construct and parse real load commands, then map their file-backed segments
// between inaccessible guard pages. A lower data segment exercises headers
// away from the reservation's start; internal holes also stay inaccessible.
fn dcb_mapping(preferred u64, is_main bool, lower bool) DcbMapping {
	page := u64(C.getpagesize())
	mut bytes := []u8{len: int(page * 3)}
	defer { unsafe { bytes.free() } }
	dcb_put32(mut bytes, 0, 0xfeedfacf)
	dcb_put32(mut bytes, 4, 0x100000c)
	dcb_put32(mut bytes, 12, if is_main { u32(2) } else { u32(6) })
	dcb_put32(mut bytes, 16, u32(4 + int(is_main) + int(lower)))
	dcb_put32(mut bytes, 24, 0x85 | if is_main { u32(0x200000) } else { u32(0) })
	text := preferred + if lower { page * 2 } else { u64(0) }
	data := text + page * 2
	mut at := 32
	if is_main { at = dcb_segment(mut bytes, at, '__PAGEZERO', 0, preferred, 0, 0, 0, false) }
	if lower { at = dcb_segment(mut bytes, at, '__LOW', preferred, page, page, page, 1, false) }
	at = dcb_segment(mut bytes, at, '__TEXT', text, page, 0, page, 5, false)
	at = dcb_segment(mut bytes, at, '__DATA', data, page, page * 2, page, 1, true)
	dcb_put32(mut bytes, at, 0x32)
	dcb_put32(mut bytes, at + 4, 24)
	dcb_put32(mut bytes, at + 8, 2)
	dcb_put32(mut bytes, at + 12, 0x110000)
	dcb_put32(mut bytes, at + 16, 0x110000)
	at += 24
	if is_main {
		dcb_put32(mut bytes, at, 0x80000028)
		dcb_put32(mut bytes, at + 4, 24)
		dcb_put64(mut bytes, at + 8, 1024)
		at += 24
	} else {
		install := '@rpath/libImages.dylib'
		size := (24 + install.len + 1 + 7) & ~7
		dcb_put32(mut bytes, at, 0xd)
		dcb_put32(mut bytes, at + 4, u32(size))
		dcb_put32(mut bytes, at + 8, 24)
		dcb_put32(mut bytes, at + 16, 0x10000)
		dcb_put32(mut bytes, at + 20, 0x10000)
		dcb_text(mut bytes, at + 24, install)
		at += size
	}
	dcb_put32(mut bytes, 20, u32(at - 32))
	dcb_put32(mut bytes, 1024, 0xd65f03c0) // RET; this fixture executes no image code.
	for i in 0 .. 64 { bytes[int(page * 2) + 32 + i] = u8(i + 1) }
	image := macho.parse(bytes) or { panic(err) }
	layout := image.layout(page) or { panic(err) }
	region := C.mmap(unsafe { nil }, usize(layout.size + page * 2), C.PROT_NONE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert region != unsafe { voidptr(-1) }
	base := u64(region) + page
	for segment in image.segments {
		if segment.name == '__PAGEZERO' { continue }
		destination := base + segment.address - layout.base
		assert C.mprotect(unsafe { voidptr(destination) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { C.memcpy(voidptr(destination), &image.data[int(segment.fileoff)], usize(segment.filesize)) }
		assert C.mprotect(unsafe { voidptr(destination) }, usize(page), C.PROT_READ) == 0
	}
	return DcbMapping{image, layout, base}
}
