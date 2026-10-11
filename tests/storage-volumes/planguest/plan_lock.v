// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

#include <sys/file.h>
#include <signal.h>
fn C.flock(i32, i32) i32
fn C.pipe(&i32) i32
fn C.kill(i32, i32) i32

// The parent owns a CLOEXEC directory lock while separately executed utilities
// reopen the same inode. No inherited open description can grant them the lock.
@[direct_array_access]
fn planned_lock(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'lock baseline')
		copy_plan(c'/root/saved.vset', c'/root/locked.vset')
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'acquire directory lock')
		tool(c'plan-grow', c'/root/locked.vset', c'2', c'8192', nil, 1)
		planning_add(c'/root/locked.vset', c'0', c'20', c'7340032', c'4096', true, 1)
		simple(c'plan-remove', c'/root/locked.vset', c'12', 1)
		simple(c'plan-enroll', c'/root/locked.vset', c'/root/offline.vmap', 1)
		simple(c'plan-forget', c'/root/locked.vset', c'2', 1)
		planning_capacity(c'/root/locked.vset', c'0', parent, c'16777216', 1)
		pool_add(c'/root/locked.vset', c'4', c'0', c'7340032', c'7348224', c'4096', 1)
		tool(c'pool-remove', c'/root/locked.vset', c'3', c'0', nil, 1)
		pool_allocate(c'/root/locked.vset', c'3', c'14', c'4096', true, 1)
		pool_growth(c'/root/locked.vset', c'pool-expand', c'3', c'0', c'6299648', 1)
		pool_growth(c'/root/locked.vset', c'pool-grow', c'3', c'14', c'8192', 1)
		pool_batch(c'/root/locked.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', false, 1, nil)
		planning_allocate(c'/root/locked.vset', c'0', c'20', c'4096', c'7340032', c'7348224', c'4096', true, 1)
		simple(c'save', parent, c'/root/locked.vmap', 1)
		tool(c'save-set', c'/root/locked.vset', parent, other, nil, 1)
		pool_batch(c'/root/locked.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', true, 0, nil)
		simple(c'pool-space', c'/root/locked.vset', c'3', 0)
		simple(c'show-bundle', c'/root/locked.vset', nil, 0)
		// Lexical aliases must lock the same inode; another directory is free.
		pool_growth(c'/root/../root/locked.vset', c'pool-expand', c'3', c'0', c'6299648', 1)
		tool(c'save-set', c'/etc/vinix/lock-independent.vset', parent, other, nil, 0)
		check(C.unlink(c'/etc/vinix/lock-independent.vset') == 0, c'clean independent destination')
		bundle_unchanged(c'/root/locked.vset', &baseline[0], size)
		missing(c'/root/locked.vmap')
		check(C.close(directory) == 0, c'release directory lock')
		// The retry reads the newly published state instead of a stale candidate.
		planning_add(c'/root/locked.vset', c'0', c'20', c'7340032', c'4096', true, 0)
		pool_growth(c'/root/locked.vset', c'pool-expand', c'3', c'0', c'6299648', 0)
		simple(c'plan-remove', c'/root/locked.vset', c'20', 0)
		tool(c'pool-remove', c'/root/locked.vset', c'3', c'0', nil, 0)
		tool(c'pool-remove', c'/root/locked.vset', c'3', c'1', nil, 0)
		pool_members(c'/root/locked.vset')
		bundle_unchanged(c'/root/locked.vset', &baseline[0], size)
		missing(c'/dev/mapper/vinix20')
		// A killed lock owner requires no stale lock-file cleanup.
		mut ready := [2]i32{}
		mut release := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&release[0]) == 0, c'lock owner barriers')
		child := C.fork()
		check(child >= 0, c'fork lock owner')
		if child == 0 {
			C.close(ready[0]); C.close(release[1])
			held := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
			if held < 0 || C.flock(held, C.LOCK_EX | C.LOCK_NB) != 0 || C.write(ready[1], c'1', 1) != 1 { C._exit(2) }
			mut byte := u8(0)
			C.read(release[0], &byte, 1)
			C._exit(3)
		}
		check(C.close(ready[1]) == 0 && C.close(release[0]) == 0, c'parent barrier descriptors')
		mut byte := u8(0)
		check(C.read(ready[0], &byte, 1) == 1 && byte == `1` && C.close(ready[0]) == 0, c'lock owner ready')
		pool_growth(c'/root/locked.vset', c'pool-expand', c'3', c'0', c'6299648', 1)
		check(C.kill(child, C.SIGKILL) == 0, c'terminate lock owner')
		mut code := i32(-1)
		check(C.waitpid(child, &code, 0) == child && code & 127 == C.SIGKILL && C.close(release[1]) == 0, c'reap lock owner')
		pool_growth(c'/root/locked.vset', c'pool-expand', c'3', c'0', c'6299648', 0)
		check(C.unlink(c'/root/locked.vset') == 0, c'clean lock fixture')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		C.printf(c'PLAN LOCK PASSED: directory contention, unlocked previews, independent destinations, fresh retries and killed-owner recovery\n')
	}
}
