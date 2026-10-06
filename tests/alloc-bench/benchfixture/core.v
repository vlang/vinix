// SPDX-License-Identifier: GPL-2.0-or-later
// Differential syscall/allocation fixture; never used by a timing runner.
@[has_globals]
module benchfixture

#include <fixture-native-abi.h>
struct C.vab_fixture_word { value u64 }
struct C.timespec { tv_sec i64; tv_nsec i64 }
struct C.utsname { sysname [65]char; release [65]char; machine [65]char }
fn C.VAB_FIXTURE_ERRNO() &i32
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) i32
fn C.strcpy(&char, &char) &char
fn C.strtoull(&char, voidptr, i32) u64
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.printf(&char, ...) i32
fn C.atexit(fn ()) i32
fn C.abort()
fn C.vab_fixture_finish()
__global vab_fixture_mode &char
__global vab_fixture_fail usize
__global vab_fixture_calls usize
__global vab_fixture_frees usize
__global vab_fixture_live usize
__global vab_fixture_peak usize
__global vab_fixture_pointers [64]voidptr
__global vab_fixture_ids [64]usize
__global vab_fixture_digest u64
__global vab_fixture_maps usize
__global vab_fixture_unmaps usize
__global vab_fixture_pipes usize
__global vab_fixture_closes usize
__global vab_fixture_clock usize
__global vab_fixture_tick u64
__global vab_fixture_first_fd i32
__global vab_fixture_initialized bool

fn fixture_setup() {
	unsafe {
		if vab_fixture_initialized { return }
		vab_fixture_initialized = true
		vab_fixture_mode = C.getenv(c'VAB_FAIL')
		if vab_fixture_mode == nil { vab_fixture_mode = &char(c'none') }
		index := C.getenv(c'VAB_FAIL_INDEX')
		vab_fixture_fail = if index == nil { usize(1) } else { usize(C.strtoull(index, nil, 10)) }
		if C.atexit(C.vab_fixture_finish) != 0 { C.abort() }
	}
}
fn selected(mode &char, index usize) bool { unsafe { return C.strcmp(vab_fixture_mode, mode) == 0 && index == vab_fixture_fail } }
fn errno_set(value i32) { unsafe { ptr := C.VAB_FIXTURE_ERRNO(); *ptr = value } }
fn digest(value u64) { unsafe { vab_fixture_digest = vab_fixture_digest * 1099511628211 ^ value } }

@[export: 'vab_fixture_finish']
pub fn finish() {
	unsafe {
		word := C.vab_fixture_word{value: vab_fixture_digest}
		C.printf(c'VAB-FIXTURE malloc=%zu free=%zu live=%zu peak=%zu digest=%llu mmap=%zu munmap=%zu pipe=%zu close=%zu clock=%zu\n', vab_fixture_calls, vab_fixture_frees, vab_fixture_live, vab_fixture_peak, word.value, vab_fixture_maps, vab_fixture_unmaps, vab_fixture_pipes, vab_fixture_closes, vab_fixture_clock)
		if vab_fixture_live != 0 { C.abort() }
	}
}

@[export: 'vab_fixture_malloc']
pub fn fixture_malloc(size usize) voidptr {
	unsafe {
		fixture_setup()
		vab_fixture_calls++
		digest(u64(size)); digest(u64(vab_fixture_calls))
		if selected(c'malloc', vab_fixture_calls) { errno_set(C.ENOMEM); return nil }
		ptr := C.malloc(size)
		if ptr == nil { C.abort() }
		mut slot := usize(0)
		for slot < 64 && vab_fixture_pointers[slot] != nil { slot++ }
		if slot == 64 { C.abort() }
		vab_fixture_pointers[slot] = ptr
		vab_fixture_ids[slot] = vab_fixture_calls
		vab_fixture_live++
		if vab_fixture_live > vab_fixture_peak { vab_fixture_peak = vab_fixture_live }
		return ptr
	}
}

@[export: 'vab_fixture_free']
pub fn fixture_free(ptr voidptr) {
	unsafe {
		mut slot := usize(0)
		for slot < 64 && vab_fixture_pointers[slot] != ptr { slot++ }
		if slot == 64 || ptr == nil { C.abort() }
		digest(u64(vab_fixture_ids[slot]) ^ 0x5a5a5a5a)
		vab_fixture_pointers[slot] = nil
		vab_fixture_frees++
		vab_fixture_live--
		C.free(ptr)
	}
}

@[export: 'vab_fixture_mmap']
pub fn fixture_mmap(addr voidptr, size usize, protection i32, flags i32, fd i32, offset isize) voidptr {
	unsafe {
		fixture_setup(); vab_fixture_maps++; digest(u64(size))
		if selected(c'mmap', vab_fixture_maps) { errno_set(C.ENOMEM); return voidptr(C.MAP_FAILED) }
		return C.mmap(addr, size, protection, flags, fd, offset)
	}
}

@[export: 'vab_fixture_munmap']
pub fn fixture_munmap(addr voidptr, size usize) i32 {
	unsafe {
		vab_fixture_unmaps++; digest(u64(size) ^ 0xabababab)
		result := C.munmap(addr, size)
		if selected(c'munmap', vab_fixture_unmaps) { errno_set(C.EINVAL); return -1 }
		return result
	}
}

@[export: 'vab_fixture_pipe']
pub fn fixture_pipe(descriptors &i32) i32 {
	unsafe {
		fixture_setup(); vab_fixture_pipes++
		if selected(c'pipe', vab_fixture_pipes) { errno_set(C.EMFILE); return -1 }
		result := C.pipe(descriptors)
		vab_fixture_first_fd = descriptors[0]
		return result
	}
}

@[export: 'vab_fixture_close']
pub fn fixture_close(fd i32) i32 {
	unsafe {
		vab_fixture_closes++
		digest(if fd == vab_fixture_first_fd { u64(0x1111) } else { u64(0x2222) })
		result := C.close(fd)
		if selected(c'close', vab_fixture_closes) { errno_set(if fd == vab_fixture_first_fd { i32(C.EBADF) } else { i32(C.EIO) }); return -1 }
		if C.strcmp(vab_fixture_mode, c'close_both') == 0 && vab_fixture_closes <= 2 { errno_set(if fd == vab_fixture_first_fd { i32(C.EBADF) } else { i32(C.EIO) }); return -1 }
		return result
	}
}

@[export: 'vab_fixture_clock_gettime']
pub fn fixture_clock(clock i32, value &C.timespec) i32 {
	unsafe {
		fixture_setup(); vab_fixture_clock++
		if selected(c'clock', vab_fixture_clock) { errno_set(C.EIO); return -1 }
		durations := [u64(9000), 1000, 6000, 3000, 5000, 2000, 8000]!
		vab_fixture_tick = u64((vab_fixture_clock + 1) / 2) * 1000000
		if vab_fixture_clock % 2 == 0 { vab_fixture_tick += durations[((vab_fixture_clock / 2) - 1) % 7] }
		if C.strcmp(vab_fixture_mode, c'constant_clock') == 0 { vab_fixture_tick = 1 }
		value.tv_sec = i64(vab_fixture_tick / 1000000000)
		value.tv_nsec = i64(vab_fixture_tick % 1000000000)
	}
	return 0
}

@[export: 'vab_fixture_clock_getres']
pub fn fixture_clock_res(clock i32, value &C.timespec) i32 {
	fixture_setup()
	if selected(c'resolution', 1) { errno_set(C.EINVAL); return -1 }
	unsafe { value.tv_sec = 0; value.tv_nsec = 1 }
	return 0
}

@[export: 'vab_fixture_uname']
pub fn fixture_uname(identity &C.utsname) i32 {
	fixture_setup()
	if selected(c'uname', 1) { errno_set(C.EIO); return -1 }
	unsafe {
		C.strcpy(&identity.sysname[0], c'Fixture OS=1')
		C.strcpy(&identity.release[0], c'release test')
		C.strcpy(&identity.machine[0], c'test64')
	}
	return 0
}

@[export: 'vab_fixture_sysconf']
pub fn fixture_sysconf(name i32) isize {
	fixture_setup()
	if selected(c'pagesize', 1) { errno_set(C.EINVAL); return -1 }
	return 4096
}
