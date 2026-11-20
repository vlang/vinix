// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import errno
import file
import katomic
import klock
import krandom
import proc
import usercopy

// kcmp(2) types. Mesa asks KCMP_FILE whether two DRM descriptors share one
// open-file description; checkpoint tools compare the rest.
const kcmp_file = 0
const kcmp_vm = 1
const kcmp_files = 2
const kcmp_fs = 3
const kcmp_sighand = 4
const kcmp_io = 5
const kcmp_sysvsem = 6
const kcmp_epoll_tfd = 7
const kcmp_types = 8

// Each type orders its objects by an address mixed with two random words
// chosen once, as Linux does: callers may sort by the result, but it reveals
// no kernel address and no order shared between types.
__global (
	kcmp_cookies       [16]u64
	kcmp_cookies_lock  klock.Lock
	kcmp_cookies_ready bool
)

fn kcmp_order(first u64, second u64, kind int) u64 {
	if !katomic.load(&kcmp_cookies_ready) {
		kcmp_cookies_lock.acquire()
		if !kcmp_cookies_ready {
			krandom.fill(voidptr(&kcmp_cookies[0]), sizeof(kcmp_cookies), true)
			for i := 0; i < kcmp_types; i++ {
				kcmp_cookies[2 * i + 1] |= (u64(1) << 63) | 1
			}
			katomic.store(mut &kcmp_cookies_ready, true)
		}
		kcmp_cookies_lock.release()
	}
	a := i64((first ^ kcmp_cookies[2 * kind]) * kcmp_cookies[2 * kind + 1])
	b := i64((second ^ kcmp_cookies[2 * kind]) * kcmp_cookies[2 * kind + 1])
	return if a == b { u64(0) } else if a < b { u64(1) } else { u64(2) }
}

// The objects one thread shares with others, as kcmp sees them. Vinix keeps
// the descriptor table and signal handlers per process (clone shares them
// only between threads), the filesystem view per process until a thread unshares
// CLONE_FS, and no I/O contexts (there is no ioprio_set): every task has
// none, which Linux reports as equal, as it does for tasks that never set an
// I/O priority. An undo list exists once the process has made a CLONE_SYSVSEM
// thread; see Process.sysvsem_undo.
struct KcmpTask {
mut:
	process &proc.Process = unsafe { nil }
	fs      voidptr
	vm      voidptr
}

fn kcmp_identity(kind int, task &KcmpTask) u64 {
	return match kind {
		kcmp_vm { u64(task.vm) }
		kcmp_files, kcmp_sighand { u64(voidptr(task.process)) }
		kcmp_sysvsem { if katomic.load(&task.process.sysvsem_undo) { u64(voidptr(task.process)) } else { u64(0) } }
		kcmp_fs { if task.fs != unsafe { nil } { u64(task.fs) } else { u64(voidptr(task.process)) } }
		else { u64(0) }
	}
}

// Under the process table lock: the thread with kernel id `global`. Thread.fs
// is read without the thread list lock, which allocate_tid takes before the
// table's; the address is only compared, so a freed and reused ThreadFS can
// at worst compare equal.
fn kcmp_task_locked(global int, mut task KcmpTask) u64 {
	if global <= 0 || global >= proc.max_pid { return errno.esrch }
	t := threads_by_tid[global]
	if t == unsafe { nil } || katomic.load(&t.is_dead) || t.process == unsafe { nil } {
		return errno.esrch
	}
	task.process = t.process
	task.fs = voidptr(t.fs)
	task.vm = voidptr(t.process.pagemap)
	return 0
}

// Under the process table lock, which keeps the reaper from freeing the
// descriptor array: the open-file description behind `fdnum`, as an address
// to compare (0 for none), and whether the descriptor table was busy. Its lock
// is taken before the process table's elsewhere, so it is only tried, as
// procfs does. The address is read before the lock is released: a sibling's
// close() may free the FD at once.
fn kcmp_try_handle(process &proc.Process, fdnum u32) (u64, bool) {
	mut p := unsafe { process }
	if !p.fds_lock.test_and_acquire() {
		return 0, true
	}
	mut address := u64(0)
	if u64(fdnum) < u64(p.fds.len) && p.fds[int(fdnum)] != unsafe { nil } {
		descriptor := unsafe { &file.FD(p.fds[int(fdnum)]) }
		address = u64(voidptr(descriptor.handle))
	}
	p.fds_lock.release()
	return address, false
}

// As kcmp_try_handle(), but returns the descriptor with a reference on it and
// on its description, for use after both locks are released.
fn kcmp_try_take(process &proc.Process, fdnum u32) (&file.FD, bool) {
	mut p := unsafe { process }
	if !p.fds_lock.test_and_acquire() {
		return unsafe { nil }, true
	}
	mut found := &file.FD(unsafe { nil })
	if u64(fdnum) < u64(p.fds.len) && p.fds[int(fdnum)] != unsafe { nil } {
		found = unsafe { &file.FD(p.fds[int(fdnum)]) }
		if found.handle == unsafe { nil } {
			found = unsafe { nil }
		} else {
			katomic.inc(mut &found.handle.refcount)
			katomic.inc(mut &found.refcount)
		}
	}
	p.fds_lock.release()
	return found, false
}

// Between tries for a busy descriptor table. Interrupts are enabled here, so
// a plain pause leaves shootdowns free to run.
fn kcmp_relax() {
	$if arm64 {
		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	} $else {
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
}

struct KcmpEpollSlot {
	efd  u32
	tfd  u32
	toff u32
}

// A descriptor table lock is held only briefly, so this many tries outlast
// any real contention. Running out is reported as EAGAIN.
const kcmp_attempts = 1 << 20

// kcmp(pid1, pid2, type, idx1, idx2): 0 when both tasks share the object,
// otherwise 1 or 2 by a stable but meaningless order. Errors follow Linux's
// order: ESRCH for a missing task, EPERM without inspection rights on both,
// then EINVAL for an unknown type and the type's own errors.
pub fn syscall_kcmp(_ voidptr, pid1_word u64, pid2_word u64, type_word u64, idx1 u64, idx2 u64) (u64, u64) {
	// pid_t and int arguments are the low 32 bits of their registers.
	local1 := int(i32(u32(pid1_word)))
	local2 := int(i32(u32(pid2_word)))
	kind := int(i32(u32(type_word)))
	// KCMP_EPOLL_TFD reads its slot before resolving either descriptor.
	mut slot := KcmpEpollSlot{}
	mut slot_read := false
	for attempt := 0; attempt < kcmp_attempts; attempt++ {
		if attempt > 0 { kcmp_relax() }
		mut first := KcmpTask{}
		mut second := KcmpTask{}
		// Numbers are resolved on every pass, under the lock of the lookup.
		proc.lock_table()
		mut failure := kcmp_task_locked(proc.kernel_id_locked(local1), mut first)
		if failure == 0 { failure = kcmp_task_locked(proc.kernel_id_locked(local2), mut second) }
		if failure == 0 && (!proc.may_inspect_realcreds_locked(first.process)
			|| !proc.may_inspect_realcreds_locked(second.process)) {
			failure = errno.eperm
		}
		if failure == 0 && (kind < 0 || kind >= kcmp_types) { failure = errno.einval }
		if failure != 0 {
			proc.unlock_table()
			return errno.err, failure
		}
		if kind != kcmp_file && kind != kcmp_epoll_tfd {
			result := kcmp_order(kcmp_identity(kind, &first), kcmp_identity(kind, &second), kind)
			proc.unlock_table()
			return result, 0
		}
		if kind == kcmp_epoll_tfd && !slot_read {
			// The copy may fault and sleep; it is made without the table lock.
			proc.unlock_table()
			if !usercopy.copy_from_user(voidptr(&slot), idx2, sizeof(KcmpEpollSlot)) {
				return errno.err, errno.efault
			}
			slot_read = true
			continue
		}
		left, left_busy := kcmp_try_handle(first.process, u32(idx1))
		if left_busy {
			proc.unlock_table()
			continue
		}
		if left == 0 {
			proc.unlock_table()
			return errno.err, errno.ebadf
		}
		if kind == kcmp_file {
			right, right_busy := kcmp_try_handle(second.process, u32(idx2))
			proc.unlock_table()
			if right_busy { continue }
			if right == 0 { return errno.err, errno.ebadf }
			return kcmp_order(left, right, kcmp_file), 0
		}
		// The epoll set is held by reference while its registrations are read.
		mut set, set_busy := kcmp_try_take(second.process, slot.efd)
		proc.unlock_table()
		if set_busy { continue }
		if set == unsafe { nil } { return errno.err, errno.ebadf }
		target, err := file.epoll_registration(set.handle, slot.tfd, slot.toff)
		set.unref()
		if err != 0 { return errno.err, err }
		return kcmp_order(left, target, kcmp_file), 0
	}
	return errno.err, errno.eagain
}
