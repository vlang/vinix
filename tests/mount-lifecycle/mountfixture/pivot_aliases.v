// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <pthread.h>
@[typedef]
struct C.pthread_t {}
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
struct AliasPeer { ready i32 proceed i32 old C.stat next C.stat }

fn alias_verdict(kind int, stage &char, valid bool) {
	if valid { return }
	unsafe { C.printf(c'MOUNT PIVOT ALIAS RESULT: case=%d stage=%s mismatch\n', kind, stage) }
	C.fflush(unsafe { nil })
	check(false, 290 + kind)
}

fn alias_wait(fd int) {
	mut byte := u8(0)
	check(C.read(fd, &byte, 1) == 1 && byte == `X` && C.close(fd) == 0, 295)
}

fn alias_signal(fd int) { check(C.write(fd, c'X', 1) == 1 && C.close(fd) == 0, 295) }

fn alias_policy(path &char, writable bool) {
	unsafe {
		fd := C.open(path, C.O_WRONLY)
		if writable { check(fd >= 0 && C.close(fd) == 0, 296) }
		else { check(fd == -1 && *C.__errno_location() == C.EROFS, 296) }
	}
}

fn alias_paths(kind int, old &C.stat, next &C.stat) {
	unsafe {
		for iteration in 0 .. 200 {
			root_old := kind in [0, 2]
			cwd_old := kind != 2
			alias_verdict(kind, c'root-alias', same(c'/', if root_old { old } else { next }))
			alias_verdict(kind, c'cwd-alias', same(c'.', if cwd_old { old } else { next }))
			alias_policy(c'/marker', !root_old)
			alias_policy(c'marker', !cwd_old)
		}
	}
}

fn alias_observe(kind int, old &C.stat, next &C.stat, alias_fd int) {
	alias_paths(kind, old, next)
	unsafe {
		for iteration in 0 .. 200 {
			check(C.openat(alias_fd, c'marker', C.O_WRONLY) == -1 && *C.__errno_location() == C.EROFS, 296)
		}
		check(C.close(alias_fd) == 0, 296)
	}
}

fn alias_worker(argument voidptr) voidptr {
	unsafe {
		peer := &AliasPeer(argument)
		alias_signal(peer.ready)
		alias_wait(peer.proceed)
		alias_paths(4, &peer.old, &peer.next)
		return nil
	}
}

fn pivot_alias_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 297)
		mut base := [256]char{}
		mut root := [256]char{}
		mut alias := [256]char{}
		mut next_path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/pa-%d', kind) > 0, 297)
		directory(&base[0])
		check(C.snprintf(&root[0], 256, c'%s/root', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 297)
		directory(&root[0]); directory(&alias[0])
		pivot_tree(&root[0])
		check(C.snprintf(&next_path[0], 256, c'%s/new', &root[0]) > 0, 297)
		directory(&next_path[0]); pivot_tree(&next_path[0])
		check(C.mount(&root[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0
			&& C.mount(c'none', &alias[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 297)
		mut old := C.stat{}
		mut next := C.stat{}
		check(C.stat(&root[0], &old) == 0 && same(&alias[0], &old) && C.stat(&next_path[0], &next) == 0, 297)
		old_fd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(old_fd >= 0 && alias_fd >= 0, 297)
		if kind >= 3 {
			check(C.chroot(&root[0]) == 0 && C.fchdir(alias_fd) == 0 && C.close(old_fd) == 0, 298)
			mut handle := C.pthread_t{}
			mut ready := [2]i32{}
			mut proceed := [2]i32{}
			mut peer := AliasPeer{old: old, next: next}
			if kind == 4 {
				check(C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0, 298)
				peer = AliasPeer{ready: ready[1], proceed: proceed[0], old: old, next: next}
				check(C.pthread_create(&handle, nil, alias_worker, &peer) == 0, 298)
				alias_wait(ready[0])
				check(C.unshare(int(C.CLONE_FS)) == 0, 298)
			}
			check(pivot_call(c'/new', c'/new/old') == 0, 298)
			alias_observe(kind, &old, &next, alias_fd)
			if kind == 4 { alias_signal(proceed[1]); check(C.pthread_join(handle, nil) == 0, 298) }
			return
		}
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0, 299)
		holder := C.fork()
		check(holder >= 0, 299)
		if holder == 0 {
			check(C.close(ready[0]) == 0 && C.close(proceed[1]) == 0, 299)
			check(C.chroot(if kind == 1 { &root[0] } else { &alias[0] }) == 0
				&& C.fchdir(if kind == 2 { old_fd } else { alias_fd }) == 0
				&& C.close(old_fd) == 0 && same(c'/', &old) && same(c'.', &old), 299)
			alias_signal(ready[1])
			alias_wait(proceed[0])
			alias_observe(kind, &old, &next, alias_fd)
			C._exit(0)
		}
		check(C.close(ready[1]) == 0 && C.close(proceed[0]) == 0
			&& C.close(old_fd) == 0 && C.close(alias_fd) == 0, 299)
		alias_wait(ready[0])
		check(C.chroot(&root[0]) == 0 && C.chdir(c'/') == 0
			&& pivot_call(c'/new', c'/new/old') == 0 && same(c'/', &next) && same(c'.', &next), 299)
		alias_signal(proceed[1])
		wait_child(holder)
	}
}

fn pivot_alias_cases(selected int) {
	unsafe {
		mut root := C.stat{}
		check(C.stat(c'/', &root) == 0, 300)
		for kind in 0 .. 5 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 300)
			if child == 0 { pivot_alias_case(kind); C._exit(0) }
			wait_child(child)
			check(same(c'/', &root), 300)
			C.printf(c'MOUNT PIVOT ALIAS CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT PIVOT ALIASES: PASS')
		C.fflush(nil)
	}
}
