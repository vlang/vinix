// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct C.pthread_mutex_t {}

@[typedef]
struct C.pthread_key_t {}

@[typedef]
struct C.pthread_once_t {}

type TlsInit = fn ()

fn C.pthread_once(&C.pthread_once_t, TlsInit) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_key_create(&C.pthread_key_t, fn (voidptr)) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.calloc(usize, usize) voidptr
fn C.realloc(voidptr, usize) voidptr
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.free(voidptr)

struct TlsModule {
	image       voidptr
	initialized usize
	size        usize
	align       usize
}

struct ThreadTls {
mut:
	blocks &voidptr
	count  usize
}

struct TlsIndex {
	module usize
	offset usize
}

struct TlsArgument {
mut:
	index TlsIndex
	owner voidptr
	next  &TlsArgument
}

@[cinit]
__global tls_once C.pthread_once_t = C.PTHREAD_ONCE_INIT

__global tls_lock C.pthread_mutex_t
__global tls_key C.pthread_key_t
__global tls_ready bool
__global tls_modules &TlsModule
__global tls_count usize
__global tls_arguments &TlsArgument

fn tls_destroy(pointer voidptr) {
	unsafe {
		state := &ThreadTls(pointer)
		if state == nil { return }
		for i := usize(0); i < state.count; i++ { C.free(state.blocks[i]) }
		C.free(state.blocks)
		C.free(state)
	}
}

fn tls_initialize() {
	unsafe {
		tls_ready = C.pthread_mutex_init(&tls_lock, nil) == 0 && C.pthread_key_create(&tls_key, tls_destroy) == 0
	}
}

// Module IDs remain stable for the process lifetime. Blocks are lazy and owned
// by each pthread; later dlopen calls can grow its vector without losing data.
@[export: '__tls_register_module']
pub fn tls_register(image voidptr, initialized usize, size usize, alignment i32) usize {
	unsafe {
		C.pthread_once(&tls_once, tls_initialize)
		// The Bionic linker registers every DSO, including those without a
		// PT_TLS segment. Those arrive with an empty template and zero alignment.
		if !tls_ready || alignment < 0 || (alignment == 0 && size != 0) || initialized > size || (initialized != 0 && image == nil) {
			return ~usize(0)
		}
		align := if alignment == 0 { usize(1) } else { usize(alignment) }
		if align & (align - 1) != 0 { return ~usize(0) }
		C.pthread_mutex_lock(&tls_lock)
		defer { C.pthread_mutex_unlock(&tls_lock) }
		if tls_count >= ~usize(0) / sizeof(TlsModule) - 1 { return ~usize(0) }
		modules := &TlsModule(C.realloc(tls_modules, (tls_count + 1) * sizeof(TlsModule)))
		if modules == nil { return ~usize(0) }
		tls_modules = modules
		modules[tls_count] = TlsModule{image, initialized, size, if align < sizeof(voidptr) {
			sizeof(voidptr)
		} else {
			align
		}}
		slot := tls_count
		tls_count++
		return slot
	}
}

fn tls_module(slot usize) voidptr {
	unsafe {
		C.pthread_once(&tls_once, tls_initialize)
		if !tls_ready { return nil }
		C.pthread_mutex_lock(&tls_lock)
		if slot >= tls_count {
			C.pthread_mutex_unlock(&tls_lock)
			return nil
		}
		desc := tls_modules[slot]
		count := tls_count
		C.pthread_mutex_unlock(&tls_lock)
		mut state := &ThreadTls(C.pthread_getspecific(tls_key))
		if state == nil {
			state = &ThreadTls(C.calloc(1, sizeof(ThreadTls)))
			if state == nil { return nil }
			if C.pthread_setspecific(tls_key, state) != 0 {
				C.free(state)
				return nil
			}
		}
		if slot >= state.count {
			blocks := &voidptr(C.realloc(state.blocks, count * sizeof(voidptr)))
			if blocks == nil { return nil }
			C.memset(&blocks[state.count], 0, (count - state.count) * sizeof(voidptr))
			state.blocks = blocks
			state.count = count
		}
		if state.blocks[slot] == nil {
			mut block := voidptr(nil)
			if C.posix_memalign(&block, desc.align, if desc.size == 0 {
				usize(1)
			} else {
				desc.size
			}) != 0 {
				return nil
			}
			if desc.initialized != 0 { C.memcpy(block, desc.image, desc.initialized) }
			C.memset(&u8(block) + desc.initialized, 0, desc.size - desc.initialized)
			state.blocks[slot] = block
		}
		return state.blocks[slot]
	}
}

@[export: 'bionic___tls_get_addr']
pub fn tls_address(index &TlsIndex) usize {
	unsafe {
		if index == nil { return 0 }
		base := tls_module(index.module)
		return if base == nil { usize(0) } else { usize(base) + index.offset }
	}
}

struct TlsDescriptor {
mut:
	resolver voidptr
	argument &TlsIndex
}

// The assembly entry preserves TLSDESC's stronger register ABI before calling
// this ordinary V function. An undefined weak TLS symbol has address zero.
@[export: 'vinix_ws_tlsdesc_address']
pub fn tlsdesc_address(descriptor &TlsDescriptor) usize {
	unsafe {
		index := descriptor.argument
		if index.module == ~usize(0) { return index.offset }
		address := tls_address(index)
		if address == 0 { C.abort() }
		return address
	}
}

// Descriptors belong to the referencing DSO, even when its TLS symbol comes
// from a dependency. Release their arguments on unload or failed relocation.
@[export: 'vinix_ws_release_tls_descriptors']
pub fn release_tls_descriptors(library voidptr) {
	unsafe {
		C.pthread_once(&tls_once, tls_initialize)
		if !tls_ready { return }
		C.pthread_mutex_lock(&tls_lock)
		defer { C.pthread_mutex_unlock(&tls_lock) }
		mut link := &tls_arguments
		for *link != nil {
			node := *link
			if node.owner == library {
				*link = node.next
				C.free(node)
			} else {
				link = &node.next
			}
		}
	}
}

struct TlsSymbol {
	name    u32
	info    u8
	other   u8
	section u16
	value   usize
	size    usize
}

type TlsLookup = fn (voidptr, &char, &usize) &TlsSymbol
type TlsOwner = fn (voidptr) voidptr

// TLS symbol values are offsets in the defining module, never virtual
// addresses. Handle these before the upstream loader's ordinary dlsym path.
@[export: 'vinix_ws_relocate_tls']
pub fn relocate_tls(kind u32, destination &usize, library voidptr, symbol &TlsSymbol, strings &char, addend usize, local_slot usize, slot_offset usize, lookup TlsLookup, owner TlsOwner) i32 {
	if kind != 1028 && kind != 1029 && kind != 1031 {
		// Initial-exec requires static TLS allocation, which this loader cannot
		// promise. Reject it instead of silently leaving a corrupt relocation.
		return if kind == 1030 { -1 } else { 0 }
	}
	unsafe {
		mut slot := local_slot
		mut offset := addend
		if symbol != nil {
			mut definition := symbol
			mut base := usize(0)
			mut defining_library := library
			if symbol.info >> 4 != 0 {
				definition = lookup(library, strings + symbol.name, &base)
				if definition != nil { defining_library = owner(voidptr(base)) }
			}
			if definition == nil || definition.section == 0 {
				if symbol.info >> 4 != 2 { return -1 }
				slot = ~usize(0)
			} else {
				if definition.info & 15 != 6 || defining_library == nil { return -1 }
				slot = *(&usize(&u8(defining_library) + slot_offset))
				offset += definition.value
			}
		}
		if kind == 1028 {
			*destination = slot
			return 1
		}
		if kind == 1029 {
			*destination = offset
			return 1
		}
		$if arm64 {
			C.pthread_once(&tls_once, tls_initialize)
			if !tls_ready { return -1 }
			argument := &TlsArgument(C.calloc(1, sizeof(TlsArgument)))
			if argument == nil { return -1 }
			argument.index = TlsIndex{slot, offset}
			argument.owner = library
			C.pthread_mutex_lock(&tls_lock)
			argument.next = tls_arguments
			tls_arguments = argument
			C.pthread_mutex_unlock(&tls_lock)
			descriptor := &TlsDescriptor(destination)
			descriptor.argument = &argument.index
			descriptor.resolver = voidptr(tlsdesc_resolver)
			return 1
		} $else {
			return -1
		}
	}
}
