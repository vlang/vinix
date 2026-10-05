// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module robustcore

struct Mapping {
mut:
	address voidptr
	requested usize
	padded usize
}

__global shared_mappings [512]Mapping
__global mappings_lock i32

fn C.__atomic_exchange_n(&i32, i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)

type Mmap = fn (voidptr, usize, i32, i32, i32, isize) voidptr
type Mmap64 = fn (voidptr, usize, i32, i32, i32, i64) voidptr
type Munmap = fn (voidptr, usize) i32
type Uname = fn (voidptr) i32

fn lock_mappings() {
	unsafe { for C.__atomic_exchange_n(&mappings_lock, 1, 2) != 0 { continue } }
}

fn unlock_mappings() {
	unsafe { C.__atomic_store_n(&mappings_lock, 0, 3) }
}

fn shared_length(address voidptr, length usize, protection i32, flags i32, fd i32) usize {
	if address != nil || fd < 0 || (flags & 3) != 1 ||
		(protection & 2) == 0 || length > 0xffffc000 {
		return length
	}
	guest_length := (length + 4095) & ~usize(4095)
	return (guest_length + 16383) & ~usize(16383)
}

fn remember_mapping(address voidptr, requested usize, padded usize) {
	if address == voidptr(-1) || requested == padded { return }
	lock_mappings()
	unsafe {
		for i := 0; i < 512; i++ {
			if shared_mappings[i].address == nil || usize(shared_mappings[i].address) == usize(address) {
				shared_mappings[i].address = address
				shared_mappings[i].requested = requested
				shared_mappings[i].padded = padded
				break
			}
		}
	}
	unlock_mappings()
}

fn unmap_length(address voidptr, original usize) usize {
	mut length := original
	lock_mappings()
	unsafe {
		for i := 0; i < 512; i++ {
			if usize(shared_mappings[i].address) == usize(address) &&
				(shared_mappings[i].requested == length || shared_mappings[i].padded == length) {
				length = shared_mappings[i].padded
				shared_mappings[i].address = nil
				break
			}
		}
	}
	unlock_mappings()
	return length
}

@[export: 'mmap']
pub fn mmap(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
	unsafe {
		next := Mmap(C.dlsym(voidptr(-1), c'mmap'))
		padded := shared_length(address, length, protection, flags, fd)
		result := next(address, padded, protection, flags, fd, offset)
		remember_mapping(result, length, padded)
		return result
	}
}

@[export: 'mmap64']
pub fn mmap64(address voidptr, length usize, protection i32, flags i32, fd i32, offset i64) voidptr {
	unsafe {
		next := Mmap64(C.dlsym(voidptr(-1), c'mmap64'))
		padded := shared_length(address, length, protection, flags, fd)
		result := next(address, padded, protection, flags, fd, offset)
		remember_mapping(result, length, padded)
		return result
	}
}

@[export: 'munmap']
pub fn munmap(address voidptr, length usize) i32 {
	unsafe {
		next := Munmap(C.dlsym(voidptr(-1), c'munmap'))
		return next(address, unmap_length(address, length))
	}
}

@[export: 'uname']
pub fn uname(buffer voidptr) i32 {
	unsafe {
		next := Uname(C.dlsym(voidptr(-1), c'uname'))
		result := next(buffer)
		if result == 0 && buffer != nil {
			machine := &char(usize(buffer) + 4 * 65)
			name := &char(c'x86_64')
			for i := 0; i < 7; i++ { machine[i] = name[i] }
		}
		return result
	}
}
