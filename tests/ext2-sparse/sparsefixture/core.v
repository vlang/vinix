// SPDX-License-Identifier: GPL-2.0-or-later
// Independent sparse EXT2 boundaries, mapped tails, lifetime and persistence.
@[translated; has_globals]
module sparsefixture

#include <sparse-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.vsparse_ull {}
@[typedef] struct C.vsparse_ll {}
struct C.statfs { f_type isize f_bfree u64 f_bsize isize }
struct C.stat { st_size i64 st_blocks i64 }
struct C.timespec { tv_sec i64 tv_nsec i64 }
struct C.vsparse_volatile_byte { mut: value u8 }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global block_size u64
__global capacity u64
__global positions [9]u64
const sparse_bytes = [u8(0x71), 0x92, 0x53]!
const crossing_bytes = [u8(1), 3, 5, 7, 9, 11, 13, 15, 2, 4, 6, 8, 10, 12, 14, 16]!

struct Heap { mut: size [16]isize count [16]isize large isize n i32 }
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.statfs(&char, &C.statfs) i32
fn C.fstat(i32, &C.stat) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.ftruncate(i32, i64) i32
fn C.unlink(&char) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sleep(u32) u32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.fsync(i32) i32
fn C.sync()
fn C.pause() i32

fn ull(value u64) C.vsparse_ull { unsafe { result := C.vsparse_ull{}; C.memcpy(&result, &value, 8); return result } }
fn ll(value i64) C.vsparse_ll { unsafe { result := C.vsparse_ll{}; C.memcpy(&result, &value, 8); return result } }
fn check(ok bool, line i32) {
	if !ok {
		unsafe { C.printf(c'EXT2 SPARSE FAIL line=%d errno=%d FAIL END\n', line, C.errno) }
		for { C.pause() }
	}
}

fn free_blocks() u64 {
	unsafe {
		mut filesystem := C.statfs{}
		check(C.statfs(c'/root', &filesystem) == 0 && filesystem.f_type == 0xef53, 21)
		return filesystem.f_bfree
	}
}

fn check_file(fd i32, size u64) {
	unsafe {
		mut stat := C.stat{}
		check(C.fstat(fd, &stat) == 0 && u64(stat.st_size) == size && stat.st_blocks < 64 * i64(block_size / 512), 28)
		mut observed := [64]u8{}
		for i := usize(0); i < sizeof(positions) / sizeof(positions[0]); i++ {
			offset := positions[i] * block_size + 17
			if offset + 3 > size { continue }
			check(C.pread(fd, &observed[0], 20, i64(offset - 17)) == 20, 33)
			for j in 0 .. 17 { check(observed[j] == 0, 34) }
			check(C.memcmp(&observed[17], &sparse_bytes[0], 3) == 0, 35)
		}
		check(C.pread(fd, &observed[0], sizeof(observed), i64(3 * block_size)) == isize(sizeof(observed)), 37)
		for i := usize(0); i < sizeof(observed); i++ { check(observed[i] == 0, 38) }
		if size > (u64(1) << 32) {
			check(C.pread(fd, &observed[0], sizeof(crossing_bytes), i64((u64(1) << 32) - 8)) == isize(sizeof(crossing_bytes)), 40)
			check(C.memcmp(&observed[0], &crossing_bytes[0], sizeof(crossing_bytes)) == 0, 41)
		}
		C.printf(c'EXT2 SPARSE size=%llu sectors=%lld block=%llu\n', ull(size), ll(stat.st_blocks), ull(block_size))
	}
}

fn shrink_tail() {
	unsafe {
		fd := C.open(c'/root/sparse-tail', C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o600))
		check(fd >= 0, 50)
		mut data := [64]u8{}
		C.memset(&data[0], 0xcc, sizeof(data))
		check(C.write(fd, &data[0], sizeof(data)) == isize(sizeof(data)), 52)
		page := usize(C.sysconf(C._SC_PAGESIZE))
		shared := &C.vsparse_volatile_byte(C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0))
		private := &C.vsparse_volatile_byte(C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE, fd, 0))
		check(voidptr(shared) != voidptr(C.MAP_FAILED) && voidptr(private) != voidptr(C.MAP_FAILED), 56)
		private[18].value = 0xee
		check(C.ftruncate(fd, 17) == 0, 58)
		shared[18].value = 0x77
		check(C.ftruncate(fd, 64) == 0, 60)
		check(C.pread(fd, &data[0], sizeof(data), 0) == isize(sizeof(data)), 61)
		for i in 0 .. 64 { check(data[i] == if i < 17 { u8(0xcc) } else { u8(0) }, 62) }
		check(shared[18].value == 0 && private[18].value == 0xee, 63)
		check(C.munmap(shared, page) == 0 && C.munmap(private, page) == 0, 64)
		check(C.unlink(c'/root/sparse-tail') == 0 && C.close(fd) == 0, 65)
	}
}

fn snapshot(heap &Heap) {
	unsafe {
		C.memset(heap, 0, sizeof(Heap))
		file := C.fopen(c'/proc/slabinfo', c'r')
		check(file != nil, 72)
		mut line := [256]char{}
		for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
			mut index := isize(0); mut size := isize(0); mut objects := isize(0); mut pages := isize(0)
			if C.sscanf(&line[0], c'size-%ld %ld %ld %ld', &index, &size, &objects, &pages) == 4 && heap.n < 16 {
				heap.size[heap.n] = size
				heap.count[heap.n] = objects
				heap.n++
			} else if C.sscanf(&line[0], c'large - - %ld', &pages) == 1 { heap.large = pages }
		}
		C.fclose(file)
		check(heap.n > 0, 80)
	}
}

fn cycle(fd i32) {
	unsafe {
		check(C.ftruncate(fd, i64(capacity)) == 0, 85)
		check(C.pwrite(fd, &sparse_bytes[0], sizeof(sparse_bytes), i64(capacity - block_size + 17)) == isize(sizeof(sparse_bytes)), 86)
		check(C.ftruncate(fd, 0) == 0, 87)
	}
}

fn churn() {
	unsafe {
		fd := C.open(c'/root/sparse-churn', C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o600))
		check(fd >= 0, 93)
		available := free_blocks()
		for _ in 0 .. 32 { cycle(fd) }
		C.sleep(6)
		mut before := Heap{}; mut after := Heap{}
		snapshot(&before)
		mut start := C.timespec{}; mut end := C.timespec{}
		check(C.clock_gettime(C.CLOCK_MONOTONIC, &start) == 0, 100)
		for _ in 0 .. 500 { cycle(fd) }
		check(C.clock_gettime(C.CLOCK_MONOTONIC, &end) == 0, 102)
		C.sleep(6)
		snapshot(&after)
		check(before.n == after.n && after.large - before.large < 16, 105)
		mut kept := isize(0)
		for i in 0 .. before.n {
			delta := after.count[i] - before.count[i]
			C.printf(c'EXT2 SPARSE CHURN size=%ld delta=%ld\n', before.size[i], delta)
			check(delta < 64, 110)
			if delta > 0 { kept += delta * before.size[i] }
		}
		check(kept < 65536 && free_blocks() == available, 113)
		elapsed_ms := (end.tv_sec - start.tv_sec) * i64(1000) + (end.tv_nsec - start.tv_nsec) / i64(1000000)
		C.printf(c'EXT2 SPARSE CHURN runs=500 retained=%ld elapsed_ms=%lld\n', kept, ll(elapsed_ms))
		check(elapsed_ms < 60000, 116)
		check(C.unlink(c'/root/sparse-churn') == 0 && C.close(fd) == 0, 117)
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		$if amd64 {
			console := C.open(c'/dev/com1', C.O_WRONLY)
			check(console >= 0 && C.dup2(console, 1) == 1 && C.dup2(console, 2) == 2, 125)
			C.close(console)
		}
		mut filesystem := C.statfs{}
		check(C.statfs(c'/root', &filesystem) == 0 && filesystem.f_type == 0xef53, 129)
		block_size = u64(filesystem.f_bsize)
		check(block_size == 1024 || block_size == 4096, 131)
		p := block_size / 4
		capacity = (12 + p + p * p + p * p * p) * block_size
		logical := [u64(11), 12, 12 + p - 1, 12 + p, 12 + p + p * p - 1, 12 + p + p * p,
			12 + p + p * p + p * p + 2 * p + 3, (u64(1) << 32) / block_size - 2, capacity / block_size - 1]!
		C.memcpy(&positions[0], &logical[0], sizeof(logical))
		mut state := [2]u64{}
		stage := C.open(c'/root/sparse-stage', C.O_CREAT | C.O_RDWR, i32(0o600))
		check(stage >= 0, 140)
		got := C.pread(stage, &state[0], sizeof(state), 0)
		check(got == 0 || got == isize(sizeof(state)), 142)
		step := if state[0] == 0 { &char(c'create') } else if state[0] == 1 { &char(c'shrink') } else { &char(c'cleanup') }
		C.printf(c'EXT2 SPARSE START %s\n', step)
		mut fd := C.open(c'/root/sparse-persist', C.O_CREAT | C.O_RDWR, i32(0o600))
		check(fd >= 0, 146)
		small := (12 + p + 1) * block_size + 20
		if state[0] == 0 {
			check(C.pwrite(stage, &state[0], sizeof(state), 0) == isize(sizeof(state)), 149)
			state[1] = free_blocks()
			shrink_tail()
			churn()
			check(C.ftruncate(fd, i64(capacity)) == 0, 153)
			mut stat := C.stat{}
			check(C.fstat(fd, &stat) == 0 && u64(stat.st_size) == capacity && stat.st_blocks == 0, 155)
			C.errno = 0
			check(C.ftruncate(fd, i64(capacity + 1)) == -1 && C.errno == C.EFBIG, 156)
			for i := usize(0); i < sizeof(positions) / sizeof(positions[0]); i++ {
				check(C.pwrite(fd, &sparse_bytes[0], sizeof(sparse_bytes), i64(positions[i] * block_size + 17)) == isize(sizeof(sparse_bytes)), 158)
			}
			check(C.pwrite(fd, &crossing_bytes[0], sizeof(crossing_bytes), i64((u64(1) << 32) - 8)) == isize(sizeof(crossing_bytes)), 159)
			check(C.pwrite(fd, &sparse_bytes[0], 0, i64(capacity)) == 0, 160)
			check_file(fd, capacity)
			state[0] = 1
		} else if state[0] == 1 {
			check_file(fd, capacity)
			check(C.ftruncate(fd, i64(small)) == 0, 165)
			check_file(fd, small)
			state[0] = 2
		} else {
			check(state[0] == 2, 169)
			check_file(fd, small)
			check(C.ftruncate(fd, 0) == 0, 171)
			mut stat := C.stat{}
			check(C.fstat(fd, &stat) == 0 && stat.st_size == 0 && stat.st_blocks == 0, 173)
			check(free_blocks() == state[1], 174)
			check(C.unlink(c'/root/sparse-persist') == 0, 175)
			check(C.close(fd) == 0, 176)
			fd = -1
			state[0] = 3
		}
		check(C.pwrite(stage, &state[0], sizeof(state), 0) == isize(sizeof(state)), 180)
		check((fd < 0 || C.fsync(fd) == 0) && C.fsync(stage) == 0, 181)
		C.sync()
		C.printf(c'EXT2 SPARSE DONE %s ino=0\n', step)
		for { C.pause() }
	}
}
