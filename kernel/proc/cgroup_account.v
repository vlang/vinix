// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the cgroup controllers enforce. The hierarchy itself lives in fs (see
// fs/cgroup.v), but the code that has to act on a limit -- the scheduler for
// cpu.max and cgroup.freeze, fork for pids.max, the memory code for
// memory.max -- cannot import fs, so each cgroup keeps its controller state in
// one of these, and every process points at its group's.
//
// Limits are hierarchical, as in Linux: a group is held to its own limits and
// to every ancestor's, so each check walks up the chain. Chains are a few
// levels deep (a runtime's parent group and the container's).
@[has_globals]
module proc

import klock
import cgcontrol
import kbudget
import katomic
import lib

pub const cgroup_default_cpu_period_ns = u64(100000000)

pub struct CGroupAccount {
pub mut:
	group_data voidptr
	control cgcontrol.Group
	parent &CGroupAccount = unsafe { nil }
	lock   klock.Lock
	// cgroup.freeze, as written to this group. A group is frozen when it or
	// any ancestor is.
	freeze u32
	// cpu.max. A zero quota means no limit. The period's usage is reset at each
	// period boundary, and a group that uses its quota up is not scheduled
	// again until `throttled_until_ns`.
	cpu_quota_ns       u64
	cpu_period_ns      u64 = cgroup_default_cpu_period_ns
	period_start_ns    u64
	period_used_ns     u64
	throttled_until_ns u64
	// cpu.stat.
	user_ns      u64
	system_ns    u64
	usage_ns     u64
	nr_periods   u64
	nr_throttled u64
	throttled_ns u64
	// pids.max, -1 for no limit, and how often a fork ran into it.
	pids_max        i64 = -1
	pids_max_events u64
	// memory.max, 0 for no limit, and memory.events.
	memory_max             u64
	memory_oom_group       bool
	memory_events_max      u64
	memory_events_oom      u64
	memory_events_oom_kill u64
	memory_peak            u64
	// fs's bookkeeping for enforcing memory.max: the group's last counted
	// usage and when it was counted, and the process last killed for going
	// over, so one excess does not kill a second process before the first has
	// had time to exit.
	memory_counted_bytes u64
	memory_counted_ns    u64
	oom_victim_pid       int
	oom_victim_ns        u64
}

pub fn new_cgroup_account(parent &CGroupAccount) &CGroupAccount {
	return &CGroupAccount{
		parent: unsafe { parent }
		control: cgcontrol.Group{parent: cgroup_control(parent)}
	}
}

// Frozen by its own cgroup.freeze or by an ancestor's.
pub fn (account &CGroupAccount) is_frozen() bool {
	mut current := unsafe { account }
	for current != unsafe { nil } {
		if katomic.load(&current.freeze) != 0 {
			return true
		}
		current = current.parent
	}
	return false
}

// Whether the scheduler has to leave a thread of `process` off the CPU now: its
// group, or one above it, is frozen or has used up its CPU quota for the
// period. The scheduler only applies this to a thread stopped in userspace,
// so nothing is ever parked in the middle of a syscall.
pub fn cgroup_holds_back(process &Process, now_ns u64) bool {
	if process == unsafe { nil } {
		return false
	}
	mut current := process.cgroup_account
	for current != unsafe { nil } {
		if katomic.load(&current.freeze) != 0 {
			return true
		}
		if katomic.load(&current.throttled_until_ns) > now_ns {
			return true
		}
		current = current.parent
	}
	return false
}

// Charge the CPU time a thread has used since it was last charged to its
// group and every group above, and throttle any whose quota for the current
// period is gone. Called on every scheduler tick for the thread on the CPU and
// when it leaves the CPU, so a thread that never gives the CPU up is still
// charged as it goes.
pub fn charge_cgroup_cpu(mut t Thread, now_ns u64) {
	since := t.cgroup_charged_ns
	t.cgroup_charged_ns = now_ns
	if since == 0 || now_ns <= since || t.cpu_group == unsafe { nil } {
		return
	}
	span := now_ns - since
	mut current := t.cpu_group
	for current != unsafe { nil } {
		current.charge_cpu(span, now_ns)
		current = current.parent
	}
}

fn (mut account CGroupAccount) charge_cpu(span u64, now_ns u64) {
	account.lock.acquire()
	defer {
		account.lock.release()
	}
	period := account.cpu_period_ns
	if period == 0 {
		return
	}
	if account.period_start_ns == 0 {
		account.period_start_ns = now_ns
	}
	if now_ns >= account.period_start_ns + period {
		elapsed := (now_ns - account.period_start_ns) / period
		account.period_start_ns += elapsed * period
		account.period_used_ns = 0
		account.nr_periods += elapsed
	}
	if account.cpu_quota_ns == 0 {
		return
	}
	account.period_used_ns += span
	period_end := account.period_start_ns + period
	if account.period_used_ns >= account.cpu_quota_ns
		&& katomic.load(&account.throttled_until_ns) < period_end {
		katomic.store(mut &account.throttled_until_ns, period_end)
		account.nr_throttled++
		cgcontrol.note_cpu(mut account.control)
		if period_end > now_ns {
			account.throttled_ns += period_end - now_ns
		}
	}
}

// Mode boundaries use the hardware CPU clock, rather than labelling the
// whole scheduler interval with the interrupt handler's current mode.
fn charge_cgroup_mode(t &Thread, span u64, kernel bool) {
	mut current := t.cpu_group
	for current != unsafe { nil } {
		current.lock.acquire()
		current.usage_ns += span
		if kernel { current.system_ns += span } else { current.user_ns += span }
		current.lock.release()
		current = current.parent
	}
}

// Set cpu.max. A new limit starts a new period, so a group that was throttled
// under the old one is released.
pub fn (mut account CGroupAccount) set_cpu_max(quota_ns u64, period_ns u64) {
	account.lock.acquire()
	defer {
		account.lock.release()
	}
	account.cpu_quota_ns = quota_ns
	account.cpu_period_ns = if period_ns == 0 { cgroup_default_cpu_period_ns } else { period_ns }
	account.period_start_ns = 0
	account.period_used_ns = 0
	katomic.store(mut &account.throttled_until_ns, u64(0))
	cgcontrol.reconfigured(mut account.control)
}

// cpu.stat, from the counters this group has kept.
pub fn (mut account CGroupAccount) cpu_stat_text() string {
	account.lock.acquire()
	usage := account.usage_ns / 1000
	user := account.user_ns / 1000
	system := account.system_ns / 1000
	periods := account.nr_periods
	throttled := account.nr_throttled
	throttled_us := account.throttled_ns / 1000
	account.lock.release()
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(160) }
	text.add('usage_usec ')
	text.add_unsigned(u64(usage))
	text.add('\nuser_usec ')
	text.add_unsigned(user)
	text.add('\nsystem_usec ')
	text.add_unsigned(system)
	text.add('\nnr_periods ')
	text.add_unsigned(u64(periods))
	text.add('\nnr_throttled ')
	text.add_unsigned(u64(throttled))
	text.add('\nthrottled_usec ')
	text.add_unsigned(u64(throttled_us))
	text.add_byte(`\n`)
	return text.str()
}

// Is `process` in `account`, directly or through a group below it?
pub fn process_in_account(process &Process, account &CGroupAccount) bool {
	mut current := process.cgroup_account
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(account) {
			return true
		}
		current = current.parent
	}
	return false
}

// The tasks -- threads, as Linux counts them -- in `account` and every group
// below it. What pids.current reports and pids.max is held to.
pub fn cgroup_task_count(account &CGroupAccount) int {
	return int(cgcontrol.snapshot(cgroup_control(account)).pids)
}

pub fn cgroup_control(account &CGroupAccount) &cgcontrol.Group {
	return if account == unsafe { nil } { unsafe { nil } } else { unsafe { &account.control } }
}

// Early checks save construction work; publication below is authoritative.
pub fn cgroup_may_add_task(process &Process) bool {
	return process == unsafe { nil } || cgroup_account_may_add_task(process.cgroup_account)
}

pub fn cgroup_account_may_add_task(account &CGroupAccount) bool {
	group := cgroup_control(account)
	return cgcontrol.may_reserve(group, 0, 1)
}

// Called only under pid_lock. Exec transfers its old slot instead of asking
// for another task, so it still works with pids.max at or below current.
fn reserve_cgroup_task(mut t Thread, replacing &Thread) bool {
	if t.process == unsafe { nil } { return true }
	group := cgroup_control(t.process.cgroup_account)
	if replacing != unsafe { nil } && replacing.quota_reserved {
		mut old := unsafe { replacing }
		t.quota_group = old.quota_group
		t.cpu_group = old.cpu_group
		t.io_until_ns = old.io_until_ns
		t.io_epoch = old.io_epoch
		t.io_debt_group = old.io_debt_group
		t.memory_until_ns = old.memory_until_ns
		t.quota_pid = old.quota_pid
		t.quota_reserved = true
		old.quota_reserved = false
		kbudget.retire_thread_group(mut old.kernel_charge)
		return true
	}
	if !cgcontrol.reserve(group, 0, 1) { return false }
	t.quota_group = group
	t.cpu_group = t.process.cgroup_account
	t.quota_pid = t.process.pid
	t.quota_reserved = true
	return true
}

fn release_cgroup_task(mut t Thread) {
	kbudget.retire_thread_group(mut t.kernel_charge)
	if !t.quota_reserved { return }
	cgcontrol.release(t.quota_group, 0, 1)
	t.quota_reserved = false
}

// Membership, task reservations and creator-owned kernel buffers move as one
// transaction. Caller holds pid_lock; failed admission changes no membership.
pub fn move_cgroup_locked(mut process Process, account &CGroupAccount, group voidptr) bool {
	if process.constructing { return false }
	mut tasks := u64(0)
	for t in threads_by_tid {
		if t != unsafe { nil } && t.quota_pid == process.pid && t.quota_reserved { tasks++ }
	}
	if !kbudget.bind_group_memory(process.kernel_owner, cgroup_control(account), tasks, process.cgroup_anonymous_bytes) { return false }
	mut old := process.cgroup_account
	for old != unsafe { nil } {
		katomic.store(mut &old.memory_counted_ns, u64(0))
		old = old.parent
	}
	mut target := unsafe { account }
	for target != unsafe { nil } {
		katomic.store(mut &target.memory_counted_ns, u64(0))
		target = target.parent
	}
	for pointer in threads_by_tid {
		mut t := unsafe { pointer }
		if t != unsafe { nil } && t.quota_pid == process.pid && t.quota_reserved {
			t.quota_group = cgroup_control(account)
			t.cpu_group = unsafe { account }
			t.io_until_ns = 0
			t.memory_until_ns = 0
		}
	}
	process.cgroup = group
	process.cgroup_account = unsafe { account }
	return true
}

// Called under pid_lock when exit/exec detaches its old address space. Cache
// invalidation makes quota recovery independent of a subsequent proc read.
pub fn forget_cgroup_memory_locked(mut process Process) {
	cgcontrol.forget_memory(cgroup_control(process.cgroup_account), process.cgroup_anonymous_bytes)
	process.cgroup_anonymous_bytes = 0
	process.cgroup_paged_bytes = 0
	mut current := process.cgroup_account
	for current != unsafe { nil } {
		katomic.store(mut &current.memory_counted_ns, u64(0))
		current = current.parent
	}
}

// memory.max is enforced by fs, which can count what a group's processes have
// resident; the memory code calls in through this hook as a process commits
// more. The hook returns false when the caller itself was chosen to
// be killed for it, and the allocation should fail.
__global (
	cgroup_memory_hook voidptr
)

type CGroupMemoryHook = fn (&Process, u64) bool

pub fn set_cgroup_memory_hook(hook voidptr) {
	cgroup_memory_hook = hook
}

// Whether `process` is in a cgroup below the root, where its memory is
// accounted. The memory code fills such a process' private anonymous memory
// in as it is touched, as Linux does, so that memory.current and memory.max
// see what it uses rather than everything its runtime has set aside. That has
// to hold from before a limit is set: runc writes memory.max only once the
// container's init has its Go runtime up.
pub fn cgroup_accounts_memory(process &Process) bool {
	return process != unsafe { nil } && process.cgroup_account != unsafe { nil }
}

// Whether `process` is held to a memory.max, its group's or an ancestor's.
fn cgroup_memory_limited(process &Process) bool {
	if process == unsafe { nil } || cgroup_memory_hook == unsafe { nil } {
		return false
	}
	mut current := process.cgroup_account
	for current != unsafe { nil } {
		if katomic.load(&current.memory_max) != 0 || cgcontrol.snapshot(cgroup_control(current)).memory_high != ~u64(0) {
			return true
		}
		current = current.parent
	}
	return false
}

// `process` has just committed about `bytes` more. True unless its group is
// over memory.max and the process was killed for it.
pub fn cgroup_charge_memory(process &Process, bytes u64) bool {
	if !cgroup_memory_limited(process) {
		return true
	}
	hook := unsafe { CGroupMemoryHook(cgroup_memory_hook) }
	return hook(process, bytes)
}
