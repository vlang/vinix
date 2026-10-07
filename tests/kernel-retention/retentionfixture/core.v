// SPDX-License-Identifier: GPL-2.0-or-later
// Independent directory/procfs semantics and retained-object workload.
@[translated]
module retentionfixture

#include <retention-native-abi.h>

@[typedef]
struct C.FILE {}

@[typedef]
struct C.vret_dirent64 {
	length u16
	name   [1]char
}

@[c_extern]
__global C.stdout &C.FILE

@[c_extern]
__global C.errno i32

struct Heap {
mut:
	sizes   [32]isize
	objects [32]isize
	large   isize
	count   i32
}

// Records contain native 64-bit fields. Each accepted record length is a
// multiple of eight, so the first record establishes alignment for the bank.
@[aligned: 8]
struct DirectoryScratch {
mut:
	bytes [128]u8
}

fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memchr(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.syscall(isize, ...) isize
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.puts(&char) i32
fn C.pause() i32

fn check(ok bool, line i32) bool {
	if !ok { unsafe { C.printf(c'FAIL: retention line=%d errno=%d\n', line, C.errno) } }
	return ok
}

fn snapshot(heap &Heap) i32 {
	unsafe {
		file := C.fopen(c'/proc/slabinfo', c'r')
		if !check(file != nil, 22) { return 1 }
		mut line := [256]char{}
		mut saw_large := i32(0)
		C.memset(heap, 0, sizeof(Heap))
		for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
			mut label := isize(0)
			mut size := isize(0)
			mut objects := isize(0)
			mut pages := isize(0)
			if C.sscanf(&line[0], c'size-%ld %ld %ld %ld', &label, &size, &objects, &pages) == 4 && label == size {
				if !check(heap.count < 32, 28) { return 1 }
				heap.sizes[heap.count] = size
				heap.objects[heap.count] = objects
				heap.count++
			} else if C.sscanf(&line[0], c'large - - %ld', &pages) == 1 {
				heap.large = pages
				saw_large = 1
			}
		}
		if !check(C.fclose(file) == 0, 34) { return 1 }
		$if arm64 {
			if !check(heap.count == 18 && saw_large != 0, 36) { return 1 }
		} $else {
			if !check(heap.count == 14 && saw_large != 0, 38) { return 1 }
		}
		return 0
	}
}

fn listing() i32 {
	unsafe {
		fd := C.open(c'/tmp/retention/entries', C.O_RDONLY | C.O_DIRECTORY)
		if !check(fd >= 0, 46) { return 1 }
		mut buffer := DirectoryScratch{}
		mut seen := [128]u8{}
		mut total := i32(0)
		C.errno = 0
		if !check(C.syscall(isize(C.SYS_getdents64), fd, &buffer.bytes[0], i32(1)) == -1 && C.errno == C.EINVAL, 49) {
			return 1
		}
		for {
			length := C.syscall(isize(C.SYS_getdents64), fd, &buffer.bytes[0], sizeof(buffer.bytes))
			if !check(length >= 0, 52) { return 1 }
			if length == 0 { break }
			for at := isize(0); at < length; {
				if !check(length - at >= 20, 55) { return 1 }
				entry := &C.vret_dirent64(&buffer.bytes[at])
				if !check(entry.length >= 20 && isize(entry.length) <= length - at && (entry.length & 7) == 0, 57) {
					return 1
				}
				name := &entry.name[0]
				if !check(C.memchr(name, 0, usize(entry.length - 19)) != nil, 58) { return 1 }
				if C.strcmp(name, c'.') != 0 && C.strcmp(name, c'..') != 0 {
					mut number := u32(0)
					mut trailing := char(0)
					if !check(C.sscanf(name, c'file-%u%c', &number, &trailing) == 1 && number < 128 && seen[number] == 0, 61) {
						return 1
					}
					seen[number] = 1
					total++
				}
				at += isize(entry.length)
			}
		}
		if !check(total == 128 && C.close(fd) == 0, 67) { return 1 }
		return 0
	}
}

fn proc_reads() i32 {
	unsafe {
		paths := [&char(c'/proc/self/stat'), &char(c'/proc/self/status'), &char(c'/proc/meminfo'),
			&char(c'/proc/uptime'), &char(c'/proc/self/maps'), &char(c'/proc/stat')]!
		mut buffer := [4096]char{}
		for i in 0 .. 6 {
			fd := C.open(paths[i], C.O_RDONLY)
			if !check(fd >= 0, 76) { return 1 }
			mut count := isize(0)
			mut total := isize(0)
			for {
				count = C.read(fd, &buffer[0], sizeof(buffer))
				if count <= 0 { break }
				total += count
			}
			if !check(count == 0 && total > 0 && C.close(fd) == 0, 79) { return 1 }
		}
		return 0
	}
}

fn trace(op &char, start i32) {
	unsafe {
		file := C.fopen(if start != 0 {
			&char(c'/proc/allocstart')
		} else {
			&char(c'/proc/allocsites')
		}, c'r')
		if file == nil { return }
		mut line := [512]char{}
		for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
			if start == 0 { C.printf(c'PERF-SITE retention op=%s %s', op, &line[0]) }
		}
		C.fclose(file)
	}
}

fn measure(name &char, operation fn () i32) i32 {
	unsafe {
		for _ in 0 .. 20 { if !check(operation() == 0, 97) { return 1 } }
		mut before := Heap{}
		mut after := Heap{}
		trace(name, 1)
		if !check(snapshot(&before) == 0, 100) { return 1 }
		for _ in 0 .. 200 { if !check(operation() == 0, 101) { return 1 } }
		if !check(snapshot(&after) == 0 && before.count == after.count, 102) { return 1 }
		mut growth := i32(0)
		for i in 0 .. before.count {
			if !check(before.sizes[i] == after.sizes[i], 105) { return 1 }
			kept := after.objects[i] - before.objects[i]
			C.printf(c'PERF-RETENTION op=%s class=%ld objects=%ld bytes=%ld\n', name, before.sizes[i], kept, kept * before.sizes[i])
			growth |= if kept > 0 { i32(1) } else { i32(0) }
		}
		C.printf(c'PERF-RETENTION op=%s large-pages=%ld\n', name, after.large - before.large)
		growth |= if after.large > before.large { i32(1) } else { i32(0) }
		trace(name, 0)
		return growth
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		if !check(C.mkdir(c'/tmp/retention', 0o700) == 0, 119) { return 1 }
		if !check(C.mount(c'tmpfs', c'/tmp/retention', c'tmpfs', 0, nil) == 0, 120) { return 1 }
		if !check(C.mkdir(c'/tmp/retention/entries', 0o700) == 0, 121) { return 1 }
		for i in 0 .. 128 {
			mut name := [96]char{}
			C.snprintf(&name[0], sizeof(name), c'/tmp/retention/entries/file-%03d', i32(i))
			fd := C.open(&name[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
			if !check(fd >= 0 && C.close(fd) == 0, 124) { return 1 }
		}
		listing_failed := measure(c'getdents64', listing)
		proc_failed := measure(c'proc_read', proc_reads)
		if !check(listing_failed == 0 && proc_failed == 0, 128) { return 1 }
		C.puts(c'KERNEL RETENTION: PASS')
		for { C.pause() }
	}
}
