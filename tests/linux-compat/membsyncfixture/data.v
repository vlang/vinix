// SPDX-License-Identifier: GPL-2.0-or-later
module membsyncfixture

const global_barrier = u64(1 << 0)
const global_expedited = u64(1 << 1)
const register_global = u64(1 << 2)
const private_expedited = u64(1 << 3)
const register_private = u64(1 << 4)
const all_registrations = register_global | register_private | register_sync_core
const memory_rounds = 256

struct MemoryExchange {
mut:
	ready i32
	start i32
	done i32
	first_store i32
	second_store i32
	second_read i32
}

fn memory_peer(arg voidptr) voidptr {
	unsafe {
		mut shared := &MemoryExchange(arg)
		pin(1)
		C.__atomic_store_n(&shared.ready, 1, 3)
		for round in 1 .. memory_rounds + 1 {
			for C.__atomic_load_n(&shared.start, 2) != round {}
			C.__atomic_store_n(&shared.second_store, 1, 0)
			seen := C.__atomic_load_n(&shared.first_store, 0)
			C.__atomic_store_n(&shared.second_read, seen, 0)
			C.__atomic_store_n(&shared.done, i32(round), 3)
		}
		return nil
	}
}

fn memory_order(command u64) {
	unsafe {
		bytes := sizeof(MemoryExchange)
		mapping := C.mmap(nil, bytes, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)
		need(isize(mapping) != -1, c'map shared data for memory ordering test')
		mut shared := &MemoryExchange(mapping)
		pin(0)
		mut worker := C.pthread_t{}
		mut child := i32(0)
		if command == private_expedited {
			need(C.pthread_create(&worker, nil, memory_peer, mapping) == 0, c'start private memory peer')
		} else {
			child = C.fork()
			need(child >= 0, c'fork global memory peer')
			if child == 0 {
				if command == global_expedited {
					need(barrier(register_global, 0) == 0, c'register target of global expedited')
				}
				memory_peer(mapping)
				C._exit(0)
			}
		}
		for C.__atomic_load_n(&shared.ready, 2) == 0 {}
		for round in 1 .. memory_rounds + 1 {
			C.__atomic_store_n(&shared.first_store, 0, 0)
			C.__atomic_store_n(&shared.second_store, 0, 0)
			C.__atomic_store_n(&shared.start, i32(round), 3)
			// The remote CPU does a relaxed store followed by a relaxed
			// load. A completed barrier must prevent both loads seeing zero.
			C.__atomic_store_n(&shared.first_store, 1, 0)
			need(barrier(command, 0) == 0, c'complete cross-CPU data memory barrier')
			seen := C.__atomic_load_n(&shared.second_store, 0)
			for C.__atomic_load_n(&shared.done, 2) != round {}
			need(seen != 0 || C.__atomic_load_n(&shared.second_read, 0) != 0,
				c'both store-load sequences cannot read the old value')
		}
		if command == private_expedited {
			need(C.pthread_join(worker, nil) == 0, c'join private memory peer')
		} else {
			mut status := i32(-1)
			need(C.waitpid(child, &status, 0) == child && status == 0, c'join global memory peer')
		}
		need(C.munmap(mapping, bytes) == 0, c'unmap shared memory ordering data')
	}
}
