// SPDX-License-Identifier: GPL-2.0-or-later
module weightedcachefixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__atomic_load_n(&u8, i32) u8
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.dprintf(i32, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.ftruncate(i32, i64) i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mkdir(&char, u32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.munmap(voidptr, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pwrite(i32, voidptr, u64, i64) i64
fn C.puts(&char) i32
fn C.rmdir(&char) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.umount(&char) i32
fn C.unlink(&char) i32
fn C.usleep(u32) i32
fn C.write(i32, voidptr, u64) i64

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.dprintf(2, c'LINUX WEIGHTEDCACHE FAIL: %s errno=%d\n', label, *C.__errno_location())
		C._exit(1)
	}
}

fn weight(node int, value &char) {
	path := if node == 0 { c'/sys/kernel/mm/mempolicy/weighted_interleave/node0' }
		else { c'/sys/kernel/mm/mempolicy/weighted_interleave/node1' }
	fd := C.open(path, C.O_WRONLY | C.O_CLOEXEC)
	need(fd >= 0 && C.write(fd, value, 1) == 1 && C.close(fd) == 0, c'update node weight')
}

fn set_policy(mode i64, mask u64) i64 {
	return C.syscall(i64(C.SYS_set_mempolicy), mode, unsafe { &mask }, u64(64))
}

fn node_at(address u64, flags u64) i32 {
	mut value := i32(-1)
	need(C.syscall(i64(C.SYS_get_mempolicy), unsafe { &value }, u64(0), u64(0),
		address, flags) == 0, c'query placement node')
	return value
}

fn load_page(address u64) {
	need(unsafe { C.__atomic_load_n(&u8(address), 0) } == 0, c'read a sparse file page')
}

fn check_cache(base u64, alias u64, page u64, other bool, reference bool) {
	load_page(base)
	load_page(alias)
	weight(0, c'3')
	if other { weight(1, c'2') }
	mask := if other { u64(3) } else { u64(1) }
	need(set_policy(6, mask) == 0, c'start weighted allocation cursor')
	need(node_at(0, 1) == 0 && node_at(0, 1) == 0, c'query does not advance the fresh cursor')
	positions := [u64(7), 2, 10, 4, 11, 6, 1, 9, 3, 8, 5]!
	expected := [i32(0), 0, 0, 1, 1, 0, 1, 1, 0, 1, 1]!
	mut seen := u64(0)
	for index in 0 .. positions.len {
		position := unsafe { positions[index] }
		address := base + position * page
		mut resident := u8(255)
		need(C.mincore(voidptr(address), page, unsafe { &resident }) == 0 && resident & 1 == 0,
			c'allocation position starts cold')
		next := node_at(0, 1)
		// Linux also spends turns on kernel allocations made during a fault.
		// Its next-node query is the control for the following cold page.
		want := if reference { next } else if other { unsafe { expected[index] } } else { i32(0) }
		load_page(address)
		placed := node_at(address, 3)
		if next != want || placed != want {
			unsafe {
				C.dprintf(2, c'LINUX WEIGHTEDCACHE DETAIL: slot=%d offset=%lu expected=%d next=%d placed=%d\n',
					i32(index), position, want, next, placed)
			}
		}
		need(next == want && placed == want, c'cold file pages follow allocation order')
		seen |= u64(1) << placed
		after := node_at(0, 1)
		alias_address := alias + position * page
		load_page(alias_address)
		need(node_at(alias_address, 3) == placed && node_at(0, 1) == after,
			c'cache-hit alias keeps both the physical node and cursor')
		if index == 0 {
			need(set_policy(6, 0) == -1 && unsafe { *C.__errno_location() } == C.EINVAL,
				c'reject empty weighted policy mask')
			need(reference || node_at(0, 1) == after, c'invalid policy preserves the active turn')
			weight(0, c'1')
		}
	}
	need(seen == mask, c'cold file allocations visit every selected node')
	need(set_policy(6, mask) == 0 && node_at(0, 1) == 0, c'reinstalling the policy resets the cursor')
	if other {
		need(set_policy(6, 2) == 0 && node_at(0, 1) == 1, c'cursor starts on the first allowed node')
		load_page(base + 12 * page)
		need(node_at(base + 12 * page, 3) == 1 && node_at(0, 1) == 1, c'single-node policy wraps in its mask')
	}
	need(set_policy(0, 0) == 0, c'restore ordinary task placement')
	weight(0, c'0')
	if other { weight(1, c'0') }
}

fn policy_matches(address u64, mode i32, mask u64) bool {
	mut actual_mode := i32(-1)
	mut actual_mask := ~u64(0)
	return C.syscall(i64(C.SYS_get_mempolicy), unsafe { &actual_mode }, unsafe { &actual_mask },
		u64(64), address, u64(2)) == 0 && actual_mode == mode && actual_mask == mask
}

fn check_private_file_policy(fd i32, page u64, other bool) {
	unsafe {
		need(C.ftruncate(fd, i64(36 * page)) == 0, c'extend the private policy source')
		need(set_policy(6, 1) == 0, c'keep cache allocation on node zero')
		byte := u8(19)
		for index in 20 .. 35 {
			need(C.pwrite(fd, &byte, 1, i64(u64(index) * page)) == 1, c'write source bytes')
		}
		base := u64(C.mmap(nil, 17 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE, fd, i64(19 * page)))
		cache := u64(C.mmap(nil, 17 * page, C.PROT_READ, C.MAP_PRIVATE, fd, i64(19 * page)))
		need(base != ~u64(0) && cache != ~u64(0), c'map private file and cache alias')
		for index in 1 .. 16 {
			address := cache + u64(index) * page
			need(*(&u8(address)) == byte && node_at(address, 3) == 0, c'cache data starts on node zero')
		}

		set_mask := if other { u64(3) } else { u64(1) }
		weight(0, c'3')
		if other { weight(1, c'2') }
		need(C.syscall(i64(C.SYS_mbind), base + page, 15 * page, i64(6), &set_mask,
			u64(64), u64(0)) == 0, c'bind explicit policy to private file offsets')
		need(policy_matches(base, 0, 0) && policy_matches(base + 16 * page, 0, 0),
			c'policy leaves surrounding private pages alone')
		for step in 0 .. 15 {
			index := u64(step * 7 % 15) + 1
			address := base + index * page
			need(policy_matches(address, 6, set_mask) && policy_matches(cache + index * page, 0, 0),
				c'policy belongs to the selected private mapping')
			if step % 2 == 0 {
				need(*(&u8(address)) == byte && node_at(address, 3) == 0,
					c'private reads share the existing cache page')
			}
			*(&u8(address)) = 42
			want := if !other || (19 + index) % 5 < 3 { i32(0) } else { i32(1) }
			need(node_at(address, 3) == want && *(&u8(address)) == 42,
				c'copy-on-write placement follows the original file offset')
			need(*(&u8(cache + index * page)) == byte && node_at(cache + index * page, 3) == 0,
				c'private writes preserve original cache data and position')
		}
		need(C.munmap(voidptr(base), 17 * page) == 0 && C.munmap(voidptr(cache), 17 * page) == 0
			&& set_policy(0, 0) == 0, c'release private file policy test')
		weight(0, c'0')
		if other { weight(1, c'0') }
		C.puts(c'LINUX WEIGHTEDCACHE PRIVATE: PASS')
	}
}

fn release_volume(path &char) {
	for _ in 0 .. 100 {
		if C.umount(path) == 0 {
			need(C.rmdir(path) == 0, c'remove the test mountpoint')
			return
		}
		// EXT2 waits for the zero-link inode to retire after unlink.
		need(unsafe { *C.__errno_location() } == C.EBUSY, c'unmount the test volume')
		C.usleep(100000)
	}
	need(false, c'wait for the test inode to retire')
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		if reference {
			need(C.mkdir(c'/sys', 0o755) == 0 && C.mount(c'sysfs', c'/sys', c'sysfs', 0, nil) == 0,
				c'mount Linux sysfs')
		}
		page := u64(C.sysconf(C._SC_PAGESIZE))
		need(page >= 4096, c'get native page size')
		mut allowed := u64(0)
		need(C.syscall(i64(C.SYS_get_mempolicy), u64(0), &allowed, u64(64), u64(0), u64(4)) == 0
			&& allowed & 1 != 0, c'query allowed nodes')
		other := allowed & 2 != 0
		path := c'/tmp/weighted-volume'
		need(C.mkdir(path, 0o755) == 0, c'create private mountpoint')
		if reference {
			// Ramfs exercises Linux's ordinary file cache in a diskless guest.
			need(C.mount(c'ramfs', path, c'ramfs', 0, nil) == 0, c'mount Linux ramfs')
		} else {
			device := $if arm64 { c'/dev/vda' } $else { c'/dev/sd0' }
			need(C.mount(device, path, c'ext2', 0, nil) == 0, c'mount private ext2 disk')
		}
		file := c'/tmp/weighted-volume/cache-probe'
		fd := C.open(file, C.O_RDWR | C.O_CREAT | C.O_EXCL, u32(0o600))
		need(fd >= 0 && C.ftruncate(fd, i64(16 * page)) == 0, c'create sparse mapping source')
		base := C.mmap(nil, 16 * page, C.PROT_READ, C.MAP_PRIVATE, fd, 0)
		alias := C.mmap(nil, 16 * page, C.PROT_READ, C.MAP_PRIVATE, fd, 0)
		need(base != voidptr(-1) && alias != voidptr(-1)
			&& C.madvise(base, 16 * page, C.MADV_RANDOM) == 0 && C.madvise(alias, 16 * page, C.MADV_RANDOM) == 0,
			c'map two aliases without readahead')
		check_cache(u64(base), u64(alias), page, other, reference)
		need(C.munmap(base, 16 * page) == 0 && C.munmap(alias, 16 * page) == 0,
			c'release cache test views')
		check_private_file_policy(fd, page, other)
		need(C.close(fd) == 0 && C.unlink(file) == 0,
			c'release the test mapping and file')
		release_volume(path)
		if other { C.puts(c'LINUX WEIGHTEDCACHE NUMA: PASS') }
		C.puts(c'LINUX WEIGHTEDCACHE SUMMARY: cursor=checked order=checked cached=checked')
		C.puts(if reference { c'LINUX WEIGHTEDCACHE REFERENCE: PASS' } else { c'LINUX WEIGHTEDCACHE: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
