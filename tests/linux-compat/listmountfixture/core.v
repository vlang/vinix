// SPDX-License-Identifier: GPL-2.0-or-later
module listmountfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.chdir(&char) i32
fn C.chroot(&char) i32
fn C.close(i32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.umount2(&char, i32) i32
fn C.unshare(i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const sys_listmount = i64(458)
const root_id = u64(-1)
const min_unique_id = u64(0x80000000)
const guard = u64(0x12345678abcdef01)
const unique_mask = u32(0x4000)

struct Request {
mut:
	size u32 = 32
	spare u32
	id u64 = root_id
	cursor u64
	namespace_id u64
}

struct ExtendedRequest {
mut:
	request Request
	tail u64
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX LISTMOUNT FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn list(request voidptr, output voidptr, count u64, flags u64) i64 {
	result := C.syscall(sys_listmount, request, output, count, flags)
	return if result >= 0 { result } else { unsafe { -i64(*C.__errno_location()) } }
}

fn mount_id(path &char) u64 {
	unsafe {
		mut words := [32]u64{}
		ret := C.syscall(i64(C.SYS_statx), i64(C.AT_FDCWD), path, u64(0), u64(unique_mask), &words[0])
		need(ret == 0 && u32(words[0]) & unique_mask != 0 && words[18] > min_unique_id,
			c'read unique mount ID')
		return words[18]
	}
}

fn tmpfs(path &char) {
	need(C.mkdir(path, 0o755) == 0, c'create mountpoint')
	need(C.mount(c'tmpfs', path, c'tmpfs', 0, unsafe { nil }) == 0, c'attach tmpfs')
}

fn check_abi(leaf u64) {
	unsafe {
		mut buffer := [2]u64{init: guard}
		mut req := Request{}
		need(list(nil, nil, 1_000_001, 2) == -C.EINVAL, c'unknown flags precede count')
		need(list(nil, nil, 1_000_001, 0) == -C.EOVERFLOW, c'oversized count precedes pointers')
		need(list(nil, &buffer[0], 1, 0) == -C.EFAULT, c'bad request pointer')
		need(list(&req, voidptr(1), 1, 0) == -C.EFAULT, c'copyout fault')
		need(list(&req, nil, 0, 0) == 0, c'zero capacity accepts NULL')
		req.size = 23
		need(list(&req, &buffer[0], 1, 0) == -C.EINVAL, c'reject short version')
		req.size = u32(C.sysconf(C._SC_PAGESIZE)) + 1
		need(list(&req, &buffer[0], 1, 0) == -C.E2BIG, c'reject version above page size')
		req.size = 24
		req.spare = 1
		need(list(&req, &buffer[0], 1, 0) == -C.EINVAL, c'reject reserved field')
		req.spare = 0
		req.id = min_unique_id
		need(list(&req, &buffer[0], 1, 0) == -C.EINVAL, c'ordinary ID is invalid')
		req.id = root_id
		req.cursor = min_unique_id
		need(list(&req, &buffer[0], 1, 0) == -C.EINVAL, c'ordinary cursor is invalid')
		req.cursor = 0
		req.id = root_id - 1
		need(list(&req, &buffer[0], 1, 0) == -C.ENOENT, c'unknown mount')
		req.id = root_id
		req.namespace_id = root_id
		need(list(&req, &buffer[0], 1, 0) == 1 && buffer[1] == guard,
			c'version zero ignores the next field and copies one ID')
		req.size = 32
		need(list(&req, &buffer[0], 1, 0) == -C.ENOENT, c'unknown namespace')
		req.namespace_id = 0
		mut future := ExtendedRequest{request: Request{size: 40}}
		need(list(&future, &buffer[0], 1, u64(1) << 32) == 1,
			c'zero extension and only the low flag word are accepted')
		future.tail = 1
		need(list(&future, &buffer[0], 1, 0) == -C.E2BIG, c'nonzero extension is rejected')
		req.id = leaf
		need(list(&req, nil, 1, 0) == 0, c'a leaf has nothing to copy to NULL')
	}
}

fn check_order(parent u64, first u64, second u64, third u64, fourth u64) {
	unsafe {
		mut req := Request{id: parent}
		mut buffer := [64]u64{init: guard}
		need(list(&req, &buffer[0], 64, 0) == 4 && buffer[0] == first && buffer[1] == second
			&& buffer[2] == third && buffer[3] == fourth && buffer[4] == guard,
			c'large output is ordered and copies only the result')
		need(list(&req, &buffer[0], 2, 0) == 2 && buffer[0] == first && buffer[1] == second,
			c'ascending first page')
		req.cursor = second
		need(list(&req, &buffer[0], 2, 0) == 2 && buffer[0] == third && buffer[1] == fourth,
			c'ascending continuation excludes its cursor')
		req.cursor = fourth
		need(list(&req, &buffer[0], 2, 0) == 0, c'ascending exhaustion')
		req.cursor = root_id
		need(list(&req, &buffer[0], 1, 0) == 1 && buffer[0] == first, c'maximum forward cursor wraps')
		req.cursor = 0
		need(list(&req, &buffer[0], 2, 1) == 2 && buffer[0] == fourth && buffer[1] == third,
			c'descending first page')
		req.cursor = third
		need(list(&req, &buffer[0], 2, 1) == 2 && buffer[0] == second && buffer[1] == first,
			c'descending continuation')
		req.cursor = first
		need(list(&req, &buffer[0], 2, 1) == 0, c'descending exhaustion')
		req.id = root_id
		req.cursor = 0
		total := list(&req, &buffer[0], 64, 0)
		need(total >= 5 && total <= 64, c'root enumeration includes all fixtures')
		mut found_parent := false
		for i in 0 .. int(total) {
			if i > 0 { need(buffer[i - 1] < buffer[i], c'root enumeration strictly ordered') }
			if buffer[i] == parent { found_parent = true }
		}
		need(found_parent, c'root enumeration contains the parent mount')
	}
}

fn check_chroot(outside u64, moved u64, inside u64) {
	unsafe {
		mut ready := [2]i32{}
		mut gate := [2]i32{}
		need(C.pipe(&ready[0]) == 0 && C.pipe(&gate[0]) == 0, c'open chroot synchronization pipes')
		child := C.fork()
		need(child >= 0, c'fork chroot probe')
		if child == 0 {
			C.close(ready[0])
			C.close(gate[1])
			need(C.chroot(c'/tmp/listmount/jail') == 0 && C.chdir(c'/') == 0, c'enter chroot')
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop capabilities in the chroot')
			mut signal := u8(1)
			need(C.write(ready[1], &signal, 1) == 1 && C.read(gate[0], &signal, 1) == 1, c'wait for parent overmount')
			mut req := Request{}
			mut ids := [8]u64{}
			need(list(&req, &ids[0], 8, 0) == 3 && ids[0] == moved && ids[1] == inside && ids[2] > inside,
				c'root enumeration uses the saved chroot after an overmount')
			req.id = outside
			need(list(&req, &ids[0], 8, 0) == -C.EPERM, c'ordinary caller cannot query an outside mount')
			req.id = inside
			need(list(&req, &ids[0], 8, 0) == 0, c'inside leaf can be queried')
			C._exit(0)
		}
		C.close(ready[1])
		C.close(gate[0])
		mut signal := u8(0)
		need(C.read(ready[0], &signal, 1) == 1 && signal == 1, c'wait for saved chroot')
		need(C.mount(c'tmpfs', c'/tmp/listmount/jail', c'tmpfs', 0, nil) == 0, c'overmount the saved chroot')
		need(C.write(gate[1], &signal, 1) == 1, c'release chroot probe')
		C.close(ready[0])
		C.close(gate[1])
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'chroot probe passed')
		need(C.umount2(c'/tmp/listmount/jail', C.MNT_DETACH) == 0, c'uncover the jail')
	}
}

fn check_namespace(old_id u64) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork mount namespace probe')
		if child == 0 {
			need(C.unshare(C.CLONE_NEWNS) == 0, c'copy namespace')
			fresh := mount_id(c'/tmp/listmount')
			mut req := Request{id: old_id}
			mut ids := [8]u64{}
			need(fresh != old_id && list(&req, &ids[0], 8, 0) == -C.ENOENT,
				c'source namespace ID is absent from the copy')
			req.id = fresh
			need(list(&req, &ids[0], 8, 0) == 4, c'enumerate descendants of the copied mount')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'mount namespace probe passed')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(sizeof(Request) == 32, c'mount ID request ABI size')
		tmpfs(c'/tmp/listmount')
		tmpfs(c'/tmp/listmount/one')
		tmpfs(c'/tmp/listmount/one/child')
		need(C.mkdir(c'/tmp/listmount/two', 0o755) == 0
			&& C.mount(c'/tmp/listmount/one/child', c'/tmp/listmount/two', nil, C.MS_BIND, nil) == 0,
			c'attach a bind alias outside the original subtree')
		need(C.mkdir(c'/tmp/listmount/jail', 0o755) == 0 && C.mkdir(c'/tmp/listmount/jail/moved', 0o755) == 0,
			c'prepare interior chroot')
		tmpfs(c'/tmp/listmount/jail/inside')
		parent := mount_id(c'/tmp/listmount')
		first := mount_id(c'/tmp/listmount/one')
		second := mount_id(c'/tmp/listmount/one/child')
		third := mount_id(c'/tmp/listmount/two')
		fourth := mount_id(c'/tmp/listmount/jail/inside')
		check_abi(second)
		check_order(parent, first, second, third, fourth)
		mut req := Request{id: first}
		mut ids := [8]u64{}
		need(list(&req, &ids[0], 8, 0) == 1 && ids[0] == second, c'only descendants of an explicit mount')
		check_namespace(parent)
		need(C.mount(c'/tmp/listmount/one/child', c'/tmp/listmount/jail/moved', nil, C.MS_MOVE, nil) == 0,
			c'move nested mount into the jail')
		need(mount_id(c'/tmp/listmount/jail/moved') == second && list(&req, &ids[0], 8, 0) == 0,
			c'move keeps the ID and changes ancestry')
		check_chroot(third, second, fourth)
		need(C.umount2(c'/tmp/listmount/jail/moved', C.MNT_DETACH) == 0, c'detach moved mount')
		req.id = second
		need(list(&req, &ids[0], 8, 0) == -C.ENOENT, c'detached mount is absent')
		req.id = parent
		req.cursor = second
		need(list(&req, &ids[0], 8, 0) == 2 && ids[0] == third && ids[1] == fourth,
			c'a detached cursor still selects later IDs')
		C.puts(c'LINUX LISTMOUNT SUMMARY: order=both chroot=filtered detach=skipped')
		C.puts(if reference { c'LINUX LISTMOUNT REFERENCE: PASS' } else { c'LINUX LISTMOUNT: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
