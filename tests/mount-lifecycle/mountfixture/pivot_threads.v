// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <alloca.h>
fn C.alloca(usize) voidptr
fn C.setns(int, int) int
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.sched_yield() i32

struct ThreadPivotChurn { mut: cycles i32 stop i32 old C.stat next C.stat }

fn thread_pivot_churn_view(argument voidptr) voidptr {
	unsafe {
		state := &ThreadPivotChurn(argument)
		check(C.unshare(int(C.CLONE_FS)) == 0, 321)
		check((same(c'/', &state.old) || same(c'/', &state.next))
			&& (same(c'.', &state.old) || same(c'.', &state.next)), 321)
		return nil
	}
}

fn thread_pivot_churn(argument voidptr) voidptr {
	unsafe {
		mut state := &ThreadPivotChurn(argument)
		for C.__atomic_load_n(&state.stop, 2) == 0 {
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, thread_pivot_churn_view, state) == 0
				&& C.pthread_join(handle, nil) == 0, 321)
			C.__atomic_fetch_add(&state.cycles, 1, 3)
		}
		return nil
	}
}

struct ThreadPivotPeer {
	kind int
	ready i32
	proceed i32
	old_fd int
	alias_fd int
	namespace_fd int
	root_path [256]char
	old C.stat
	next C.stat
}

fn thread_pivot_verdict(kind int, stage &char, valid bool) {
	if valid { return }
	unsafe { C.printf(c'MOUNT PIVOT THREAD RESULT: case=%d stage=%s mismatch\n', kind, stage) }
	C.fflush(unsafe { nil })
	check(false, 310 + kind)
}

fn thread_pivot_worker(argument voidptr) voidptr {
	unsafe {
		peer := &ThreadPivotPeer(argument)
		check(C.unshare(int(if peer.kind == 4 { C.CLONE_NEWNS } else { C.CLONE_FS })) == 0, 316)
		if peer.kind == 4 {
			check(C.mount(c'none', c'/', nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 316)
		}
		if peer.kind == 5 {
			check(C.setns(peer.namespace_fd, int(C.CLONE_NEWNS)) == 0
				&& C.chroot(&peer.root_path[0]) == 0 && C.chdir(c'/') == 0, 316)
		} else if peer.kind != 4 {
			check(C.fchdir(if peer.kind in [1, 3] { peer.alias_fd } else { peer.old_fd }) == 0
				&& C.chroot(c'.') == 0
				&& C.fchdir(if peer.kind in [1, 2] { peer.alias_fd } else { peer.old_fd }) == 0, 316)
		}
		check(same(c'/', &peer.old) && same(c'.', &peer.old), 316)
		alias_signal(peer.ready)
		alias_wait(peer.proceed)
		for iteration in 0 .. 200 {
			root_old := peer.kind in [1, 3, 4]
			cwd_old := peer.kind in [1, 2, 4]
			thread_pivot_verdict(peer.kind, c'private-root', same(c'/', if root_old { &peer.old } else { &peer.next }))
			thread_pivot_verdict(peer.kind, c'private-cwd', same(c'.', if cwd_old { &peer.old } else { &peer.next }))
			alias_policy(c'/marker', peer.kind !in [1, 3, 4])
			alias_policy(c'marker', peer.kind !in [1, 2, 4])
			check(C.openat(peer.alias_fd, c'marker', C.O_WRONLY) == -1 && *C.__errno_location() == C.EROFS, 317)
		}
		return nil
	}
}

fn thread_pivot_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 318)
		namespace_fd := C.open(c'/proc/self/ns/mnt', C.O_RDONLY)
		check(namespace_fd >= 0, 318)
		mut base := [256]char{}
		mut root := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/pt-%d', kind) > 0, 318)
		directory(&base[0])
		check(C.snprintf(&root[0], 256, c'%s/root', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 318)
		directory(&root[0]); directory(&alias[0]); pivot_tree(&root[0])
		check(C.snprintf(&path[0], 256, c'%s/new', &root[0]) > 0, 318)
		directory(&path[0]); pivot_tree(&path[0])
		mut old := C.stat{}
		mut next := C.stat{}
		check(C.stat(&root[0], &old) == 0 && C.stat(&path[0], &next) == 0
			&& C.mount(&root[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0
			&& C.mount(c'none', &alias[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0
			&& same(&alias[0], &old), 318)
		old_fd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(old_fd >= 0 && alias_fd >= 0 && C.chroot(&root[0]) == 0 && C.chdir(c'/') == 0, 318)
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0, 319)
		mut peer := &ThreadPivotPeer(C.alloca(sizeof(ThreadPivotPeer)))
		*peer = ThreadPivotPeer{kind: kind, ready: ready[1], proceed: proceed[0],
			old_fd: old_fd, alias_fd: alias_fd, namespace_fd: namespace_fd,
			root_path: root, old: old, next: next}
		mut handle := C.pthread_t{}
		if kind == 6 {
			check(C.close(ready[0]) == 0 && C.close(ready[1]) == 0
				&& C.close(proceed[0]) == 0 && C.close(proceed[1]) == 0, 321)
			mut state := &ThreadPivotChurn(C.alloca(sizeof(ThreadPivotChurn)))
			*state = ThreadPivotChurn{old: old, next: next}
			check(C.pthread_create(&handle, nil, thread_pivot_churn, state) == 0, 321)
			for C.__atomic_load_n(&state.cycles, 2) < 20 { C.sched_yield() }
			check(pivot_call(c'/new', c'/new/old') == 0 && same(c'/', &next) && same(c'.', &next), 321)
			C.__atomic_store_n(&state.stop, 1, 3)
			check(C.pthread_join(handle, nil) == 0 && C.close(old_fd) == 0
				&& C.close(alias_fd) == 0 && C.close(namespace_fd) == 0, 321)
			C.printf(c'MOUNT PIVOT THREAD CHURN: cycles=%d\n', C.__atomic_load_n(&state.cycles, 2))
			C.fflush(nil)
			return
		}
		mut holder := -1
		if kind == 5 {
			holder = C.fork()
			check(holder >= 0, 319)
			if holder == 0 {
				check(C.close(ready[0]) == 0 && C.close(proceed[1]) == 0
					&& C.unshare(int(C.CLONE_NEWNS)) == 0
					&& C.mount(c'none', c'/', nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 319)
				check(C.pthread_create(&handle, nil, thread_pivot_worker, peer) == 0
					&& C.pthread_join(handle, nil) == 0, 319)
				thread_pivot_verdict(kind, c'foreign-shared-root', same(c'/', &old))
				thread_pivot_verdict(kind, c'foreign-shared-cwd', same(c'.', &old))
				alias_policy(c'/marker', false); alias_policy(c'marker', false)
				C._exit(0)
			}
			check(C.close(ready[1]) == 0 && C.close(proceed[0]) == 0, 319)
		} else { check(C.pthread_create(&handle, nil, thread_pivot_worker, peer) == 0, 319) }
		alias_wait(ready[0])
		check(pivot_call(c'/new', c'/new/old') == 0 && same(c'/', &next) && same(c'.', &next), 319)
		alias_signal(proceed[1])
		if kind == 5 { wait_child(holder) }
		else { check(C.pthread_join(handle, nil) == 0, 319) }
		check(C.close(old_fd) == 0 && C.close(alias_fd) == 0 && C.close(namespace_fd) == 0, 319)
	}
}

fn pivot_thread_cases(selected int) {
	unsafe {
		mut root := C.stat{}
		check(C.stat(c'/', &root) == 0, 320)
		for kind in 0 .. 7 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 320)
			if child == 0 { thread_pivot_case(kind); C._exit(0) }
			wait_child(child)
			check(same(c'/', &root), 320)
			C.printf(c'MOUNT PIVOT THREAD CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT PIVOT THREADS: PASS')
		C.fflush(nil)
	}
}
