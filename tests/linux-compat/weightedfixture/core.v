// SPDX-License-Identifier: GPL-2.0-or-later
module weightedfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.dprintf(i32, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.fstat(i32, &C.stat) i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mkdir(&char, u32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.munmap(voidptr, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) u64
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const weighted_mode = i64(6)
const bind_mode = i64(2)
const default_mode = i64(0)
const node_flag = u64(1)
const address_flag = u64(2)
const allowed_flag = u64(4)

struct C.stat {
	st_mode u32
	st_size i64
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.dprintf(2, c'LINUX WEIGHTED FAIL: %s errno=%d\n', label, *C.__errno_location())
		C._exit(1)
	}
}

fn result(ret i64) i64 {
	unsafe { return if ret < 0 { -i64(*C.__errno_location()) } else { ret } }
}

fn weight_path(node int) &char {
	return if node == 0 { c'/sys/kernel/mm/mempolicy/weighted_interleave/node0' }
	else { c'/sys/kernel/mm/mempolicy/weighted_interleave/node1' }
}

fn read_weight(node int) int {
	fd := C.open(weight_path(node), C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0, c'open weight for reading')
	mut weight := 0
	mut digits := 0
	mut byte := u8(0)
	for {
		need(C.read(fd, unsafe { &byte }, 1) == 1, c'read decimal weight')
		if byte == `\n` { break }
		need(byte >= `0` && byte <= `9` && digits < 3, c'weight format has one to three decimal digits')
		weight = weight * 10 + int(byte - `0`)
		digits++
	}
	need(digits > 0 && C.read(fd, unsafe { &byte }, 1) == 0 && C.close(fd) == 0,
		c'weight ends in a newline and EOF')
	return weight
}

fn write_weight(node int, data &char) i64 {
	fd := C.open(weight_path(node), C.O_WRONLY | C.O_TRUNC | C.O_CLOEXEC)
	need(fd >= 0, c'open weight for writing with truncation')
	ret := result(C.write(fd, unsafe { voidptr(data) }, C.strlen(data)))
	need(C.close(fd) == 0, c'close weight')
	return ret
}

fn set_weight(node int, value &char) {
	need(write_weight(node, value) == i64(C.strlen(value)), c'store complete weight')
}

fn check_weight_file(page u64) {
	fd := C.open(weight_path(0), C.O_RDWR | C.O_CLOEXEC)
	need(fd >= 0, c'open weight metadata and write control')
	mut info := C.stat{}
	need(C.fstat(fd, unsafe { &info }) == 0 && info.st_mode & 0o777 == 0o644
		&& info.st_size == i64(page), c'weight file has sysfs permissions and page-sized metadata')
	buffer := C.mmap(unsafe { nil }, 2 * page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(buffer != voidptr(-1), c'map an oversized write buffer')
	unsafe { *(&u8(buffer)) = `4` }
	need(C.write(fd, buffer, page + 1) == i64(page), c'oversized write consumes one page')
	need(C.munmap(buffer, 2 * page) == 0 && C.close(fd) == 0, c'release weight control')
	need(read_weight(0) == 4, c'numeric value ends at the first NUL')
	set_weight(0, c'0')
}

fn check_weights(page u64, other bool) {
	need(read_weight(0) == 1, c'node zero defaults to weight one')
	if other { need(read_weight(1) == 1, c'second node defaults to weight one') }
	set_weight(0, c'+0xFF\n')
	need(read_weight(0) == 255, c'weight accepts a plus sign and hexadecimal')
	set_weight(0, c'040')
	need(read_weight(0) == 32, c'weight accepts octal')
	set_weight(0, c'')
	need(read_weight(0) == 32, c'zero-length write preserves weight')
	need(write_weight(0, c'256\n') == -C.EINVAL && write_weight(0, c'-1\n') == -C.EINVAL
		&& write_weight(0, c' 3\n') == -C.EINVAL && write_weight(0, c'3\n\n') == -C.EINVAL,
		c'malformed and out-of-range weights return EINVAL')
	need(read_weight(0) == 32, c'failed writes preserve weight')
	set_weight(0, c'\n')
	need(read_weight(0) == 1, c'empty line restores the default weight')
	set_weight(0, c'3')
	set_weight(0, c'0\n')
	need(read_weight(0) == 1, c'zero restores the default weight')
	check_weight_file(page)
	child := C.fork()
	need(child >= 0, c'fork an unprivileged weight reader')
	if child == 0 {
		need(C.setuid(1000) == 0, c'drop privileges')
		need(read_weight(0) == 1, c'unprivileged user can read weights')
		need(result(i64(C.open(weight_path(0), C.O_WRONLY))) == -C.EACCES,
			c'unprivileged user cannot open weights for writing')
		C._exit(0)
	}
	mut status := i32(-1)
	need(C.waitpid(child, unsafe { &status }, 0) == child && status == 0, c'weight permissions pass')
}

fn set_policy(mode i64, mask u64) i64 {
	return result(C.syscall(i64(C.SYS_set_mempolicy), mode, unsafe { &mask }, u64(64)))
}

fn get_policy(address u64, flags u64) (i32, u64) {
	mut mode := i32(-1)
	mut mask := ~u64(0)
	need(C.syscall(i64(C.SYS_get_mempolicy), unsafe { &mode }, unsafe { &mask }, u64(64),
		address, flags) == 0, c'read memory policy')
	return mode, mask
}

fn policy_is(address u64, flags u64, want_mode i64, want_mask u64) bool {
	mode, mask := get_policy(address, flags)
	return mode == i32(want_mode) && mask == want_mask
}

fn discard(base u64, length u64) {
	need(C.madvise(voidptr(base), length, C.MADV_DONTNEED) == 0, c'discard eager or previously used pages')
}

fn new_region(length u64, page u64) u64 {
	base := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(base != voidptr(-1), c'map anonymous region')
	discard(u64(base), length)
	mut resident := u8(255)
	need(C.mincore(base, page, unsafe { &resident }) == 0 && resident & 1 == 0,
		c'placement test starts on an absent page')
	return u64(base)
}

fn fault(address u64) i32 {
	unsafe { *(&u8(address)) = 28 }
	node, _ := get_policy(address, node_flag | address_flag)
	return node
}

fn check_placement(base u64, page u64, first u64, second u64) {
	// Cover three periods at weights 3:2, visiting the pages out of order.
	for step in 0 .. 15 {
		address := base + u64(step * 7 % 15) * page
		node := if address / page % (first + second) < first { i32(0) } else { i32(1) }
		need(fault(address) == node, c'weighted placement follows the address index')
	}
}

fn check_policies(page u64, other bool) {
	mask := if other { u64(3) } else { u64(1) }
	need(set_policy(weighted_mode, mask) == 0 && policy_is(0, 0, weighted_mode, mask),
		c'set and query a weighted task policy')
	need(set_policy(weighted_mode, 0) == -C.EINVAL && policy_is(0, 0, weighted_mode, mask),
		c'empty mask rejects the policy change')
	if other {
		need(set_policy(weighted_mode, 2) == 0 && policy_is(0, node_flag, 1, 2),
			c'weighted next-node query names the selected node')
		need(set_policy(weighted_mode, mask) == 0, c'restore multi-node weighted policy')
	}
	set_weight(0, c'3')
	if other { set_weight(1, c'2') }
	base := new_region(17 * page, page)
	check_placement(base, page, 3, if other { u64(2) } else { u64(0) })
	set_weight(0, c'1')
	discard(base, 17 * page)
	check_placement(base, page, 1, if other { u64(2) } else { u64(0) })
	need(set_policy(bind_mode, 1) == 0, c'bind the default task allocation to node zero')
	inner := base + page
	need(C.syscall(i64(C.SYS_mbind), inner, 15 * page, weighted_mode, unsafe { &mask },
		u64(64), u64(0)) == 0 && policy_is(inner, address_flag, weighted_mode, mask),
		c'set and query weighted range policy')
	need(result(C.syscall(i64(450), inner, page, u64(0), u64(0))) == -C.EOPNOTSUPP,
		c'weighted policies reject home-node overrides')
	discard(base, 17 * page)
	check_placement(inner, page, 1, if other { u64(2) } else { u64(0) })
	need(fault(base) == 0 && fault(base + 16 * page) == 0, c'weighted range leaves surrounding pages bound')
	need(C.munmap(voidptr(base), 17 * page) == 0 && set_policy(default_mode, 0) == 0,
		c'release weighted mappings and reset task policy')
	set_weight(0, c'0')
	if other { set_weight(1, c'0') }
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		if reference {
			need(C.mkdir(c'/sys', 0o755) == 0 || *C.__errno_location() == C.EEXIST, c'create sysfs mountpoint')
			need(C.mount(c'sysfs', c'/sys', c'sysfs', 0, nil) == 0, c'mount Linux sysfs')
		}
		page := C.sysconf(C._SC_PAGESIZE)
		need(page >= 4096, c'valid native page size')
		_, allowed := get_policy(0, allowed_flag)
		need(allowed & 1 != 0, c'node zero is available')
		other := allowed & 2 != 0
		check_weights(u64(page), other)
		check_policies(u64(page), other)
		if other { C.puts(c'LINUX WEIGHTED NUMA: PASS') }
		C.puts(c'LINUX WEIGHTED SUMMARY: sysfs=checked placement=checked')
		C.puts(if reference { c'LINUX WEIGHTED REFERENCE: PASS' } else { c'LINUX WEIGHTED: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
