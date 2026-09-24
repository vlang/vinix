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
import katomic

pub const cgroup_default_cpu_period_ns = u64(100000000)

pub struct CGroupAccount {
pub mut:
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
	if since == 0 || now_ns <= since || unsafe { t.process == nil } {
		return
	}
	span := now_ns - since
	mut current := t.process.cgroup_account
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
	account.usage_ns += span
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
		if period_end > now_ns {
			account.throttled_ns += period_end - now_ns
		}
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
}

// cpu.stat, from the counters this group has kept.
pub fn (mut account CGroupAccount) cpu_stat_text() string {
	account.lock.acquire()
	usage := account.usage_ns / 1000
	periods := account.nr_periods
	throttled := account.nr_throttled
	throttled_us := account.throttled_ns / 1000
	account.lock.release()
	return 'usage_usec ${usage}\nuser_usec ${usage}\nsystem_usec 0\nnr_periods ${periods}\nnr_throttled ${throttled}\nthrottled_usec ${throttled_us}\n'
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
	lock_table()
	defer {
		unlock_table()
	}
	mut count := 0
	for pid := 1; pid < max_pid; pid++ {
		process := processes[pid]
		if process == unsafe { nil } || process.exiting {
			continue
		}
		if process_in_account(process, account) {
			count += process.threads.len
		}
	}
	return count
}

// Whether `process` may start one more task. A group, or any above it, that
// has reached its pids.max refuses, and the fork fails with EAGAIN.
pub fn cgroup_may_add_task(process &Process) bool {
	if process == unsafe { nil } {
		return true
	}
	return cgroup_account_may_add_task(process.cgroup_account)
}

// The same for a task that starts in `account`, as CLONE_INTO_CGROUP asks.
pub fn cgroup_account_may_add_task(account &CGroupAccount) bool {
	mut current := unsafe { account }
	for current != unsafe { nil } {
		limit := katomic.load(&current.pids_max)
		if limit >= 0 && i64(cgroup_task_count(current)) + 1 > limit {
			katomic.inc(mut &current.pids_max_events)
			return false
		}
		current = current.parent
	}
	return true
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
		if katomic.load(&current.memory_max) != 0 {
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
