// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import sync

#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

fn C.pthread_key_create(voidptr, voidptr) int
fn C.pthread_key_delete(u64) int
fn C.pthread_getspecific(u64) voidptr
fn C.pthread_setspecific(u64, voidptr) int
fn C.ios_tlv_get_addr()
fn C.exit(int)
fn C._exit(int)

type ImageInitializer = fn (int, &&char, &&char, &&char)
type ImageDestructor = fn (voidptr)
type ImageExit = fn ()

struct Destructor {
	function ImageDestructor = unsafe { nil }
	argument voidptr
	dso u64
	exit_function ImageExit = unsafe { nil }
}

struct ImageRuntime {
mut:
	base u64
	path string
	image macho.Image
	layout macho.Layout
	started bool
	destructors []Destructor
	destructor_lock &sync.Mutex = unsafe { nil }
	tls_modules []&ImageTls
	tls_descriptors map[u64]TlsDescriptor
}

struct ImageTls {
mut:
	key u64
	active bool
	template []u8
}

struct TlsDescriptor {
	storage &ImageTls
	offset u64
}

__global image_runtime = unsafe { &ImageRuntime(nil) }

fn image_runtime_start(image macho.Image, layout macho.Layout, base u64) {
	image_runtime = &ImageRuntime{base: base, image: image, layout: layout,
		destructor_lock: sync.new_mutex()}
	image_runtime.destructors.flags |= .noslices
	image_runtime.tls_modules.flags |= .noslices
}

fn (loaded LoadedModule) code_address(address u64) bool {
	for segment in loaded.image.segments {
		if segment.name == '__PAGEZERO' || segment.prot & 4 == 0 { continue }
		start := loaded.base + segment.address - loaded.layout.base
		if address >= start && address - start < segment.filesize && address % 4 == 0 { return true }
	}
	return false
}

fn (loaded LoadedModule) section_address(section macho.Section) u64 {
	return loaded.base + section.address - loaded.layout.base
}

fn image_initializers(loaded &LoadedModule) ![]u64 {
	mut functions := []u64{}
	for address in loaded.image.routines {
		functions << loaded.base + address - loaded.layout.base
	}
	for segment in loaded.image.segments {
		for section in segment.sections {
			kind := section.flags & 0xff
			if kind !in [u32(9), 10, 0x16] { continue }
			stride := if kind == 0x16 { u64(4) } else { u64(8) }
			if section.size % stride != 0 || section.size / stride > 65536
				|| section.address - segment.address > segment.filesize
				|| section.size > segment.filesize - (section.address - segment.address) {
				return error('iOS: invalid initializer section')
			}
			for offset := u64(0); offset < section.size; offset += stride {
				address := if kind == 0x16 {
					loaded.base + read32(loaded.section_address(section) + offset)
				} else { read64(loaded.section_address(section) + offset) }
				if !loaded.code_address(address) { return error('iOS: initializer/terminator is not executable') }
				if kind == 10 {
					image_runtime.destructors << Destructor{exit_function: unsafe { ImageExit(voidptr(address)) }}
				} else { functions << address }
			}
		}
	}
	for address in functions {
		if !loaded.code_address(address) { return error('iOS: initializer is not executable') }
	}
	return functions
}

fn image_tls_prepare(loaded &LoadedModule) ! {
	mut first := ~u64(0)
	mut end := u64(0)
	for segment in loaded.image.segments {
		for section in segment.sections {
			kind := section.flags & 0xff
			if kind in [u32(0x11), 0x12] && section.size != 0 {
				first = if section.address < first { section.address } else { first }
				end = if section.address + section.size > end { section.address + section.size } else { end }
			}
			if kind in [u32(0x14), 0x15] && section.size != 0 {
				return error('iOS: TLS pointer/initializer sections are not implemented')
			}
		}
	}
	if end == 0 {
		if loaded.image.thread_locals { return error('iOS: TLS sections have no storage template') }
		return
	}
	if end - first > 1024 * 1024 { return error('iOS: TLS template exceeds limit') }
	mut storage := &ImageTls{template: []u8{len: int(end - first)}}
	image_runtime.tls_modules << storage
	for segment in loaded.image.segments {
		for section in segment.sections {
			kind := section.flags & 0xff
			if kind == 0x11 && section.size != 0 {
				if section.address - segment.address > segment.filesize
					|| section.size > segment.filesize - (section.address - segment.address) {
					return error('iOS: TLS data exceeds file-backed segment')
				}
				unsafe { C.memcpy(&storage.template[int(section.address - first)],
					voidptr(loaded.section_address(section)), usize(section.size)) }
			}
			if kind != 0x13 { continue }
			if section.size % 24 != 0 || section.size > 65536 * 24
				|| section.address - segment.address > segment.filesize
				|| section.size > segment.filesize - (section.address - segment.address) {
				return error('iOS: invalid TLV descriptor section')
			}
			for position := u64(0); position < section.size; position += 24 {
				descriptor := loaded.section_address(section) + position
				offset := read64(descriptor + 16)
				if offset >= end - first { return error('iOS: TLV descriptor exceeds TLS template') }
				image_runtime.tls_descriptors[descriptor] = TlsDescriptor{storage, offset}
			}
		}
	}
	if C.pthread_key_create(unsafe { voidptr(&storage.key) }, unsafe { voidptr(C.free) }) != 0 {
		return error('iOS: cannot allocate TLS key')
	}
	storage.active = true
}

@[export: 'ios_tlv_address']
fn image_tls_address(descriptor u64) u64 {
	entry := image_runtime.tls_descriptors[descriptor] or { panic('iOS: unknown TLV descriptor') }
	tls := entry.storage
	mut storage := C.pthread_getspecific(tls.key)
	if storage == unsafe { nil } {
		storage = C.malloc(usize(tls.template.len))
		if storage == unsafe { nil } { panic('iOS: cannot allocate thread-local storage') }
		unsafe { C.memcpy(storage, tls.template.data, usize(tls.template.len)) }
		if C.pthread_setspecific(tls.key, storage) != 0 {
			C.free(storage)
			panic('iOS: cannot install thread-local storage')
		}
	}
	return u64(storage) + entry.offset
}

fn image_cxa_atexit(function ImageDestructor, argument voidptr, dso u64) int {
	image_runtime.destructor_lock.lock()
	image_runtime.destructors << Destructor{function: function, argument: argument, dso: dso}
	image_runtime.destructor_lock.unlock()
	return 0
}

fn image_atexit(function ImageExit) int {
	// Never give native libc an image callback: execute() later unmaps its code.
	image_runtime.destructor_lock.lock()
	image_runtime.destructors << Destructor{exit_function: function}
	image_runtime.destructor_lock.unlock()
	return 0
}

@[noreturn]
fn image_exit(status int) {
	image_cxa_finalize(0)
	C.exit(status)
	for {}
}

@[noreturn]
fn image_immediate_exit(status int) {
	C._exit(status)
	for {}
}

fn image_cxa_finalize(dso u64) {
	// Remove before invoking: destructors may register or finalize others.
	for {
		image_runtime.destructor_lock.lock()
		mut selected := -1
		for i := image_runtime.destructors.len - 1; i >= 0; i-- {
			if dso == 0 || image_runtime.destructors[i].dso == dso { selected = i; break }
		}
		if selected < 0 { image_runtime.destructor_lock.unlock(); return }
		destructor := image_runtime.destructors[selected]
		image_runtime.destructors.delete(selected)
		image_runtime.destructor_lock.unlock()
		if destructor.exit_function != unsafe { nil } {
			destructor.exit_function()
		} else {
			destructor.function(destructor.argument)
		}
	}
}

fn image_runtime_stop() {
	// A link/protection failure must never execute a module's terminators.
	if image_runtime.started { image_cxa_finalize(0) }
	image_atfork_stop()
	for storage in image_runtime.tls_modules {
		if storage.active {
			C.free(C.pthread_getspecific(storage.key))
			C.pthread_setspecific(storage.key, unsafe { nil })
			C.pthread_key_delete(storage.key)
		}
		unsafe { storage.template.free(); free(storage) }
	}
	unsafe {
		image_runtime.destructors.free()
		image_runtime.tls_modules.free()
		image_runtime.path.free()
		image_runtime.tls_descriptors.free()
	}
	image_runtime.destructor_lock.destroy()
	C.free(image_runtime.destructor_lock)
	C.free(image_runtime)
	image_runtime = unsafe { &ImageRuntime(nil) }
}
