// SPDX-License-Identifier: GPL-2.0-only
// Uses the public ABI against a kernel built with hv_memory_fixture. Guest
// entry is deliberately disabled; allocation, file I/O and mappings are real.
@[has_globals]
module memoryguest

#include <native-abi.h>
@[typedef]
struct C.FILE {}

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_barrier_t {}

@[c_extern]
__global C.stdout &C.FILE
struct C.vinix_hv_create {
	memory_size u64
}

struct C.vinix_hv_exit {
	reason u32
}

fn C.open(&char, i32, ...) i32
fn C.ioctl(i32, usize, ...) i32
fn C.pwrite(i32, voidptr, usize, isize) isize
fn C.pread(i32, voidptr, usize, isize) isize
fn C.read(i32, voidptr, usize) isize
fn C.sscanf(&char, &char, ...) i32
fn C.usleep(u32) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_barrier_init(&C.pthread_barrier_t, voidptr, u32) i32
fn C.pthread_barrier_wait(&C.pthread_barrier_t) i32
fn C.pthread_barrier_destroy(&C.pthread_barrier_t) i32

struct Race {
mut:
	fd      i32
	barrier &C.pthread_barrier_t = unsafe { nil }
	result  i32
	error   i32
}

fn check(ok bool, line int) {
	if !ok {
		unsafe { C.printf(c'HYPERVISOR MEMORY GUEST FAIL line=%d errno=%d\n', line, *C.__errno_location()) }
		C._exit(1)
	}
}

fn slab_snapshot() [32]u64 {
	unsafe {
		mut buffer := [4096]char{}
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		check(fd >= 0, 61)
		count := C.read(fd, &buffer[0], 4095)
		check(count > 0 && C.close(fd) == 0, 63)
		mut live := [32]u64{}
		mut row := 0
		for i := 0; i < count; i++ {
			if i > 0 && buffer[i - 1] != char(10) { continue }
			mut size := u64(0)
			mut repeated_size := u64(0)
			mut objects := u64(0)
			if C.sscanf(&buffer[i], &char(C.VINIX_HV_SLAB_INPUT), &size, &repeated_size, &objects) == 3 {
				check(row < 32 && size == repeated_size, 73)
				live[row] = objects
				row++
			}
		}
		check(row > 0, 79)
		return live
	}
}

fn create_worker(argument voidptr) voidptr {
	unsafe {
		mut race := &Race(argument)
		C.pthread_barrier_wait(race.barrier)
		mut request := C.vinix_hv_create{ memory_size: 16 * 1024 * 1024 }
		race.result = C.ioctl(race.fd, usize(C.VINIX_HV_CREATE_VM), &request)
		race.error = *C.__errno_location()
		return nil
	}
}

fn exercise(iteration int) {
	unsafe {
		fd := C.open(c'/dev/hypervisor', C.O_RDWR)
		check(fd >= 0, 72)
		mut request := C.vinix_hv_create{}
		check(C.ioctl(fd, usize(C.VINIX_HV_CREATE_VM), &request) == -1 && *C.__errno_location() == C.EINVAL, 74)
		request.memory_size = u64(C.VINIX_HV_MAX_GUEST_MEMORY) + 1
		check(C.ioctl(fd, usize(C.VINIX_HV_CREATE_VM), &request) == -1 && *C.__errno_location() == C.EINVAL, 76)
		request.memory_size = 8 * 1024 * 1024 + 1
		check(C.ioctl(fd, usize(C.VINIX_HV_CREATE_VM), &request) == 0, 78)
		check(C.ioctl(fd, usize(C.VINIX_HV_CREATE_VM), &request) == -1 && *C.__errno_location() == C.EBUSY, 79)
		mut input := [8192]u8{}
		mut output := [8192]u8{}
		for i in 0 .. input.len { input[i] = u8(i * 31 + iteration + 1) }
		for offset in [isize(4093), isize(2 * 1024 * 1024 - 3), isize(8 * 1024 * 1024 - 4096)]! {
			check(C.pwrite(fd, &input[0], 8192, offset) == 8192, 84)
			check(C.pread(fd, &output[0], 8192, offset) == 8192, 85)
			for i in 0 .. input.len { check(input[i] == output[i], 86) }
		}
		check(C.pwrite(fd, &input[0], 1, 8 * 1024 * 1024 + 4096) == -1 && *C.__errno_location() == C.EFBIG, 88)
		check(C.pread(fd, &output[0], 1, 8 * 1024 * 1024 + 4096) == 0, 89)
		mut exit := C.vinix_hv_exit{}
		check(C.ioctl(fd, usize(C.VINIX_HV_RUN), &exit) == -1 && *C.__errno_location() == C.EIO, 91)
		check(C.mmap(nil, 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE, fd, 0) == voidptr(C.MAP_FAILED)
			&& *C.__errno_location() == C.EINVAL, 92)
		check(C.mmap(nil, 4096, C.PROT_READ, C.MAP_SHARED, fd, 8 * 1024 * 1024 + 4096) == voidptr(C.MAP_FAILED)
			&& *C.__errno_location() == C.EINVAL, 93)
		mapping := C.mmap(nil, 8192, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 2 * 1024 * 1024 - 4096)
		check(mapping != voidptr(C.MAP_FAILED), 93)
		mut bytes := &u8(mapping)
		bytes[4095] = 0x51
		bytes[4096] = 0xa3
		check(C.pread(fd, &output[0], 2, 2 * 1024 * 1024 - 1) == 2 && output[0] == 0x51 && output[1] == 0xa3, 97)
		copy := C.dup(fd)
		check(copy >= 0 && C.close(fd) == 0 && C.close(copy) == 0, 99)
		// The shared mapping retains the session after its last fd is closed.
		check(bytes[4095] == 0x51 && bytes[4096] == 0xa3, 101)
		if iteration == 0 {
			pid := C.fork()
			check(pid >= 0, 104)
			if pid == 0 {
				bytes[4096] = 0xe7
				C._exit(0)
			}
			mut status := i32(0)
			check(C.waitpid(pid, &status, 0) == pid && status == 0 && bytes[4096] == 0xe7, 107)
		}
		check(C.munmap(mapping, 8192) == 0, 109)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		large := C.open(c'/dev/hypervisor', C.O_RDWR)
		mut maximum := C.vinix_hv_create{ memory_size: u64(C.VINIX_HV_MAX_GUEST_MEMORY) }
		check(large >= 0 && C.ioctl(large, usize(C.VINIX_HV_CREATE_VM), &maximum) == 0, 170)
		mut edge := u8(0x8d)
		check(C.pwrite(large, &edge, 1, isize(maximum.memory_size - 1)) == 1, 172)
		edge = 0
		check(C.pread(large, &edge, 1, isize(maximum.memory_size - 1)) == 1 && edge == 0x8d, 174)
		check(C.close(large) == 0, 175)
		C.puts(c'HYPERVISOR MEMORY API MAXIMUM PASS: 1 GiB, last-byte IO')
		// Warm nodes, mappings and deferred queues, then wait beyond the five
		// second resource retirement grace before each live-allocation sample.
		exercise(0)
		_ = slab_snapshot()
		C.usleep(8_000_000)
		before := slab_snapshot()
		for iteration in 0 .. 100 { exercise(iteration) }
		fd := C.open(c'/dev/hypervisor', C.O_RDWR)
		check(fd >= 0, 119)
		mut barrier := C.pthread_barrier_t{}
		check(C.pthread_barrier_init(&barrier, nil, 2) == 0, 121)
		mut races := [Race{ fd: fd, barrier: &barrier }, Race{ fd: fd, barrier: &barrier }]!
		mut threads := [2]C.pthread_t{}
		for i in 0 .. 2 {
			check(C.pthread_create(&threads[i], nil, create_worker, &races[i]) == 0, 124)
		}
		for i in 0 .. 2 { check(C.pthread_join(threads[i], nil) == 0, 125) }
		winner := if races[0].result == 0 { 0 } else { 1 }
		check(races[winner].result == 0 && races[1 - winner].result == -1 && races[1 - winner].error == C.EBUSY, 127)
		check(C.pthread_barrier_destroy(&barrier) == 0 && C.close(fd) == 0, 128)
		pid := C.fork()
		check(pid >= 0, 130)
		if pid == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 132)
			denied := C.open(c'/dev/hypervisor', C.O_RDWR)
			check(denied == -1 && *C.__errno_location() == C.EACCES, 134)
			C._exit(0)
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && status == 0, 138)
		C.usleep(8_000_000)
		after := slab_snapshot()
		for i in 0 .. before.len {
			C.printf(&char(C.VINIX_HV_SLAB_OUTPUT), i, before[i], after[i])
			// Timer/reaper and the one pthread race introduce bounded noise.
			// One retained VM/session/box per iteration would grow by 100.
			check(after[i] <= before[i] + 4, 151)
		}
		C.puts(c'HYPERVISOR MEMORY GUEST PASS: 100 sessions, unaligned IO, shared mmap, fork, concurrent create, permissions')
		for { C.pause() }
		return 0
	}
}
