// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_lazy_entry()
fn C.ios_store_pointer(&u64, u64)

struct LazyImport {
	library string
	symbol string
	owner int
mut:
	value u64
	slots []u64
}

struct LazyRuntime {
mut:
	mapping voidptr
	size usize
	imports []LazyImport
	sealed bool
	capacity int
}

__global lazy_runtime = unsafe { &LazyRuntime(nil) }

fn lazy_start() ! {
	page := usize(C.getpagesize())
	// Each distinct lazy symbol needs bytes in its bind stream. Chained-only
	// apps reserve one page, rather than the maximum 65,536-thunk arena.
	mut count := u64(0)
	for loaded in module_runtime.modules { count += loaded.image.lazy_bind_info.size }
	capacity := if count > 65536 { 65536 } else if count == 0 { 1 } else { int(count) }
	size := (usize(capacity) * 24 + page - 1) & ~(page - 1)
	mapping := C.mmap(unsafe { nil }, size, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if mapping == unsafe { voidptr(-1) } { return error('iOS: cannot allocate lazy binding thunks') }
	lazy_runtime = &LazyRuntime{mapping: mapping, size: size, capacity: capacity}
	lazy_runtime.imports.flags |= .noslices
}

fn lazy_symbol(library string, symbol string) !u64 {
	if lazy_runtime.sealed || lazy_runtime.imports.len >= lazy_runtime.capacity { return error('iOS: lazy binding thunk limit exceeded') }
	index := lazy_runtime.imports.len
	address := u64(lazy_runtime.mapping) + u64(index) * 24
	// movz x16, index; ldr x17, literal; br x17; nop; .quad entry
	write32(address, 0xd2800010 | u32(index) << 5)
	write32(address + 4, 0x58000071)
	write32(address + 8, 0xd61f0220)
	write32(address + 12, 0xd503201f)
	unsafe { *(&u64(address + 16)) = u64(voidptr(C.ios_lazy_entry)) }
	lazy_runtime.imports << LazyImport{library: library, symbol: symbol, owner: module_runtime.binding}
	return address
}

fn lazy_register_slot(loaded &LoadedModule, offset u64, target u64) {
	start := u64(lazy_runtime.mapping)
	if target < start || target - start >= u64(lazy_runtime.imports.len) * 24 || (target - start) % 24 != 0 { return }
	for segment in loaded.image.segments {
		if segment.name == '__PAGEZERO' || segment.prot & 2 == 0 || segment.flags & 0x10 != 0 { continue }
		within := segment.address - loaded.layout.base
		if segment.size >= 8 && offset >= within && offset - within < segment.size - 7 {
			index := int((target - start) / 24)
			lazy_runtime.imports[index].slots << loaded.base + offset
			return
		}
	}
}

fn lazy_seal() ! {
	C.__builtin___clear_cache(lazy_runtime.mapping, unsafe { voidptr(u64(lazy_runtime.mapping) + lazy_runtime.size) })
	if C.mprotect(lazy_runtime.mapping, lazy_runtime.size, C.PROT_READ | C.PROT_EXEC) != 0 {
		return error('iOS: cannot protect lazy binding thunks')
	}
	lazy_runtime.sealed = true
}

@[export: 'ios_lazy_resolve']
fn lazy_resolve(index u64) u64 {
	if index >= u64(lazy_runtime.imports.len) { panic('iOS: invalid lazy binding thunk') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut item := unsafe { &lazy_runtime.imports[int(index)] }
	if item.value != 0 { return item.value }
	item.value = module_symbol(item.owner, item.library, item.symbol) or {
		panic('iOS: unsupported API reached by app: ${item.library} ${item.symbol}\n${err}')
	}
	for slot in item.slots { C.ios_store_pointer(unsafe { &u64(slot) }, item.value) }
	return item.value
}

fn lazy_stop() {
	C.munmap(lazy_runtime.mapping, lazy_runtime.size)
	for item in lazy_runtime.imports { unsafe { item.slots.free() } }
	unsafe { lazy_runtime.imports.free(); free(lazy_runtime) }
	lazy_runtime = unsafe { nil }
}
