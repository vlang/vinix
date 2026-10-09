// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import cgcontrol
import katomic
import time

pub struct CGroupIOContext {
pub:
	group &cgcontrol.Group = unsafe { nil }
	active bool
}

pub fn current_cgroup_io() &cgcontrol.Group {
	t := current_thread()
	if t == unsafe { nil } { return unsafe { nil } }
	if t.io_context_active { return t.io_context }
	return if t.process == unsafe { nil } { unsafe { nil } } else { cgroup_control(t.process.cgroup_account) }
}

// A cache writeback keeps its original dirtier's stable controller pointer.
// Nesting preserves the issuer for filesystem callbacks that use other caches.
pub fn begin_cgroup_io(group &cgcontrol.Group) CGroupIOContext {
	mut t := current_thread()
	if t == unsafe { nil } { return CGroupIOContext{} }
	previous := CGroupIOContext{group: t.io_context, active: t.io_context_active}
	t.io_context = unsafe { group }
	t.io_context_active = true
	return previous
}

pub fn end_cgroup_io(previous CGroupIOContext) {
	mut t := current_thread()
	if t == unsafe { nil } { return }
	t.io_context = previous.group
	t.io_context_active = previous.active
}

pub fn cgroup_io_delay(t &Thread, now u64) bool {
	return katomic.load(&t.io_until_ns) > now && (katomic.load(&t.io_epoch) == cgcontrol.epoch()
		|| cgcontrol.io_pending(t.io_debt_group, now))
}

pub fn account_cgroup_io(id u64, bytes u64, write bool) {
	mut t := current_thread()
	if bytes == 0 || t == unsafe { nil } { return }
	group := current_cgroup_io()
	if group == unsafe { nil } { return }
	until, epoch := cgcontrol.account_io(group, id, bytes, write, time.monotonic_ns())
	if until > t.io_until_ns || !cgroup_io_delay(t, time.monotonic_ns()) {
		t.io_until_ns = until
		t.io_debt_group = current_cgroup_io()
	}
	t.io_epoch = epoch
}
