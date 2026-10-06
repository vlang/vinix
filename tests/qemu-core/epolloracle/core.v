// SPDX-License-Identifier: BSD-2-Clause
// Real pipe/poll host inputs; native guests use the actual epoll APIs.
@[has_globals; translated]
module epolloracle

#include <epoll-oracle-native-abi.h>
@[typedef]
struct C.epoll_data_t {
mut:
	u64 u64
}

struct C.epoll_event {
mut:
	events u32
	data   C.epoll_data_t
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

@[typedef]
struct C.vqe_const_void_p {}

@[c_extern]
__global C.errno i32

fn C.assert(bool)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, &C.epoll_event) i32
fn C.epoll_wait(i32, &C.epoll_event, i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.pause() i32
fn C.original_test_epoll_abi_and_count() i32
fn C.test_epoll_abi_and_count() i32

__global (
	epoll_fault        i32
	epoll_creates      i32
	epoll_ctls         i32
	epoll_waits        i32
	epoll_writes       i32
	epoll_reads        i32
	epoll_closes       i32
	epoll_handle       i32
	epoll_watched      i32
	epoll_saved_events u32
	epoll_saved_data   u64
)

@[export:'vqe_host_pipe']
pub fn pipe_input(out &i32) i32 {
	unsafe {
		if epoll_fault == 1 {
			C.errno = C.EIO
			return -1
		}
		return C.pipe(out)
	}
}

@[export:'vqe_host_create']
pub fn create_input(flags i32) i32 {
	unsafe {
		epoll_creates++
		C.assert(flags == C.EPOLL_CLOEXEC)
		if epoll_fault == 2 {
			C.errno = C.EIO
			return -1
		}
		$if epoll_guest ? {
			epoll_handle = C.epoll_create1(flags)
		} $else {
			epoll_handle = C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
		}
		return epoll_handle
	}
}

@[export:'vqe_host_ctl']
pub fn ctl_input(handle i32, op i32, fd i32, event &C.epoll_event) i32 {
	unsafe {
		epoll_ctls++
		C.assert(handle == epoll_handle && op == C.EPOLL_CTL_ADD)
		C.assert(event.events == C.EPOLLIN && event.data.u64 == u64(0x56494e495845504f))
		if epoll_fault == 3 {
			C.errno = C.EIO
			return -1
		}
		epoll_watched = fd
		epoll_saved_events = event.events
		epoll_saved_data = event.data.u64
		$if epoll_guest ? {
			return C.epoll_ctl(handle, op, fd, event)
		} $else {
			return 0
		}
	}
}

@[export:'vqe_host_wait']
pub fn wait_input(handle i32, events &C.epoll_event, maxevents i32, timeout i32) i32 {
	unsafe {
		epoll_waits++
		C.assert(handle == epoll_handle && maxevents == 4)
		C.assert(timeout == if epoll_waits == 2 { 1000 } else { 0 })
		if epoll_waits <= 2 {
			for i := usize(0); i < usize(4) * sizeof(C.epoll_event); i++ {
				C.assert((&u8(events))[i] == 0xa5)
			}
		}
		if (epoll_fault == 4 && epoll_waits == 1) || (epoll_fault == 6 && epoll_waits == 2) || (epoll_fault == 11 && epoll_waits == 3) {
			C.errno = C.EIO
			return -1
		}
		mut result := i32(0)
		$if epoll_guest ? {
			result = C.epoll_wait(handle, events, maxevents, timeout)
		} $else {
			mut descriptor := C.pollfd{ fd: epoll_watched, events: i16(C.POLLIN) }
			result = C.poll(&descriptor, 1, timeout)
			if result == 1 {
				events[0] = C.epoll_event{ events: epoll_saved_events, data: C.epoll_data_t{ u64: epoll_saved_data } }
			}
		}
		if epoll_fault == 7 && epoll_waits == 2 { events[0].events = 0 }
		if epoll_fault == 8 && epoll_waits == 2 { events[0].data.u64 = events[0].data.u64 ^ u64(1) }
		return result
	}
}

@[export:'vqe_host_write']
pub fn write_input(fd i32, native_data C.vqe_const_void_p, len usize) isize {
	unsafe {
		epoll_writes++
		if epoll_fault == 5 {
			C.errno = C.EIO
			return -1
		}
		mut data := voidptr(nil)
		C.memcpy(&data, &native_data, sizeof(C.vqe_const_void_p))
		return C.write(fd, data, len)
	}
}

@[export:'vqe_host_read']
pub fn read_input(fd i32, data voidptr, len usize) isize {
	unsafe {
		epoll_reads++
		if epoll_fault == 9 {
			C.errno = C.EIO
			return -1
		}
		result := C.read(fd, data, len)
		if epoll_fault == 10 && result == 1 { *(&u8(data)) = `f` }
		return result
	}
}

@[export:'vqe_host_close']
pub fn close_input(fd i32) i32 {
	unsafe {
		epoll_closes++
		if (epoll_fault >= 12 && epoll_closes == epoll_fault - 11) {
			C.errno = C.EIO
			return -1
		}
		return C.close(fd)
	}
}

fn attempt(original bool, fault i32) [8]u64 {
	unsafe {
		mut endpoints := [2]i32{}
		C.assert(C.pipe(&endpoints[0]) == 0)
		C.fflush(nil)
		child := C.fork()
		C.assert(child >= 0)
		if child == 0 {
			C.close(endpoints[0])
			epoll_fault = fault
			epoll_creates = 0
			epoll_ctls = 0
			epoll_waits = 0
			epoll_writes = 0
			epoll_reads = 0
			epoll_closes = 0
			epoll_handle = -1
			epoll_watched = -1
			C.errno = C.E2BIG
			result := if original {
				C.original_test_epoll_abi_and_count()
			} else {
				C.test_epoll_abi_and_count()
			}
			mut report := [u64(result), u64(u32(C.errno)), u64(epoll_creates), u64(epoll_ctls),
				u64(epoll_waits), u64(epoll_writes), u64(epoll_reads), u64(epoll_closes)]!
			C.assert(C.write(endpoints[1], &report[0], sizeof(report)) == isize(sizeof(report)))
			C.fflush(nil)
			C._exit(0)
		}
		C.close(endpoints[1])
		mut report := [8]u64{}
		C.assert(C.read(endpoints[0], &report[0], sizeof(report)) == isize(sizeof(report)))
		C.assert(C.close(endpoints[0]) == 0)
		mut status := i32(-1)
		C.assert(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0)
		return report
	}
}

@[export:'main']
pub fn main_entry() i32 {
	unsafe {
		$if epoll_guest ? {
			mut console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			if console < 0 { console = C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY) }
			if console >= 0 {
				C.dup2(console, 1)
				C.dup2(console, 2)
				C.close(console)
			}
		}
		for fault := i32(0); fault <= 14; fault++ {
			original := attempt(true, fault)
			ported := attempt(false, fault)
			for field in 0 .. 8 { C.assert(original[field] == ported[field]) }
			C.assert(ported[0] == if fault == 0 { u64(0) } else { u64(1) })
			if fault == 0 {
				C.assert(ported[2] == 1 && ported[3] == 1 && ported[4] == 3 && ported[5] == 1 && ported[6] == 1 && ported[7] == 3)
			}
		}
		C.puts(c'QEMU CORE EPOLL DIFFERENTIAL PASS: fifteen native ABI/failure cases')
		C.fflush(nil)
		$if epoll_guest ? {
			for { C.pause() }
		}
		return 0
	}
}
