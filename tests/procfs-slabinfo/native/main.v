// SPDX-License-Identifier: GPL-2.0-or-later
module main

import perfheap
import perfreader

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <alloca.h>

fn C.alloca(u64) voidptr
fn C.pread(i32, voidptr, u64, i64) i64
fn C.dup2(i32, i32) i32
fn C.setresuid(u32, u32, u32) i32
fn C.setresgid(u32, u32, u32) i32
fn C.sysconf(i32) i64
fn C.sleep(u32) u32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn grace() { mut left := u32(13); for left != 0 { left = C.sleep(left) } }

fn semantics() ! {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		require(fd >= 0, 'slabinfo open failed')!
		defer { C.close(fd) }
		full := &u8(C.alloca(4096))
		// Reserve the complete requested range even for the final EOF probe:
		// accumulated text + maximum request + prefix/suffix guards.
		part := &u8(C.alloca(8194))
		snapshot := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		*snapshot = perfheap.Snapshot{}
		n := C.pread(fd, full, 4096, 0)
		require(n > 0 && n < 4096, 'complete slabinfo read failed')!
		perfheap.parse_snapshot(full, int(n), snapshot)!
		require(C.pread(fd, nil, 0, 0) == 0, 'zero read failed')!
		require(C.pread(fd, nil, 0, n) == 0, 'zero EOF read failed')!
		for chunk in [i32(1), 2, 7, 19, 31, 127, 4096]! {
			C.memset(part, 0xa5, 8194)
			mut offset := i64(0)
			for {
				require(offset < 4096, 'partial reads exceeded snapshot capacity')!
				// Keep the requested count constant through EOF. Positioned I/O
				// owns a count-sized bounce buffer; different chunk sizes can
				// legitimately expose different live-object counts in this file.
				got := C.pread(fd, part + 1 + offset, u64(chunk), offset)
				require(got >= 0 && got <= chunk && got <= 4096 - offset,
					'partial slabinfo length invalid')!
				if got == 0 { break }
				offset += got
			}
			perfheap.parse_snapshot(part + 1, int(offset), snapshot)!
			require(part[0] == 0xa5, 'partial read prefix guard changed')!
			for i := offset + 1; i < 8194; i++ {
				require(part[i] == 0xa5, 'partial read suffix guard changed')!
			}
			C.printf(c'SLABINFO CHUNK count=%d bytes=%ld PASS\n', chunk, offset)
		}
		require(C.pread(fd, part, 4096, i64(0x7fffffffffffffff) - 4096) == 0,
			'signed64 EOF offset failed')!
		C.printf(c'SLABINFO SEMANTICS chunks=7 bytes=%ld PASS\n', n)
	}
}

fn cohort(uid i32) ! {
	unsafe {
		before := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		after := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		*before = perfheap.Snapshot{}; *after = perfheap.Snapshot{}
		require(perfreader.warm('/proc/slabinfo', before, after)! != 0, 'reader warmup failed')!
		perfreader.select_cpu(0)!
		semantics()!
		grace()
		perfheap.read_snapshot('/proc/slabinfo', before)!
		for _ in 0 .. 200 { perfheap.read_snapshot('/proc/slabinfo', after)! }
		grace()
		perfheap.read_snapshot('/proc/slabinfo', after)!
		perfheap.qualify_flatness(before, after)!
		for i, row in before.classes {
			C.printf(c'SLABINFO CLASS uid=%d size=%lu objects=%lu/%lu pages=%lu/%lu\n',
				uid, row.size, row.objects, after.classes[i].objects, row.pages, after.classes[i].pages)
		}
		C.printf(c'SLABINFO STORAGE uid=%d large=%lu/%lu written=%lu/%lu\n', uid,
			before.large_pages, after.large_pages, before.written_after_free, after.written_after_free)
		C.printf(c'SLABINFO COHORT uid=%d reads=200 PASS\n', uid)
	}
}

fn run() ! {
	unsafe {
		fd := C.open($if arm64 { c'/dev/console' } $else { c'/dev/com1' }, C.O_WRONLY)
		require(fd >= 0 && C.dup2(fd, 1) >= 0 && C.dup2(fd, 2) >= 0, 'console setup failed')!
		if fd > 2 { C.close(fd) }
		perfheap.require_page_size(C.sysconf(C._SC_PAGESIZE))!
		original := perfreader.affinity()!
		cohort(0)!
		require(C.setresgid(1000, 1000, 1000) == 0 && C.setresuid(1000, 1000, 1000) == 0,
			'ordinary credentials failed')!
		cohort(1000)!
		perfreader.restore(original)!
		C.printf(c'SLABINFO SUMMARY cohorts=2 reads=400 PASS\n')
		C.printf(c'LINUX SLABINFO: PASS\n')
	}
}

fn main() {
	run() or { unsafe { C.printf(c'LINUX SLABINFO FAIL %s\n', &char(err.msg().str)) } }
	unsafe { C.fflush(C.stdout) }
	for { C.pause() }
}
