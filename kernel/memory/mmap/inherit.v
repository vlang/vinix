// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module mmap

import errno
import memory
import proc

// What fork(2) does with a range beyond what its mapping says, as OpenBSD's
// minherit(2) sets it and Linux's madvise(2) advice does: leave it out of the
// child, or give the child the range empty. A random number generator keeps
// its state in such a range, so that a forked child cannot repeat its
// parent's output: OpenBSD's arc4random asks for MAP_INHERIT_ZERO. The two
// settings are independent, as Linux keeps them.

// minherit(2)'s values.
pub const map_inherit_share = 0
pub const map_inherit_copy = 1
pub const map_inherit_none = 2
pub const map_inherit_zero = 3

// madvise(2)'s.
pub const madv_dontfork = 10
pub const madv_dofork = 11
pub const madv_wipeonfork = 18
pub const madv_keeponfork = 19

struct InheritChange {
	set_dont_fork    bool
	dont_fork        bool
	set_wipe_on_fork bool
	wipe_on_fork     bool
	// Every range must be private and anonymous (wipe-on-fork, as on
	// Linux), private (minherit's COPY), or shared (its SHARE).
	need_private_anonymous bool
	need_private           bool
	need_shared            bool
}

fn inherit_change_for_advice(advice int) InheritChange {
	return match advice {
		madv_dontfork { InheritChange{
				set_dont_fork: true
				dont_fork: true
			} }
		madv_dofork { InheritChange{
				set_dont_fork: true
				dont_fork: false
			} }
		madv_wipeonfork { InheritChange{
				set_wipe_on_fork: true
				wipe_on_fork: true
				need_private_anonymous: true
			} }
		else { InheritChange{
				set_wipe_on_fork: true
				wipe_on_fork: false
			} }
	}
}

// Apply `change` to [base, base + length): all of it or, on an error, none.
// A hole is ENOMEM, as madvise(2) has it; an immutable range EPERM, as
// mimmutable(2) forbids changing how a range is inherited.
fn set_inheritance_unlocked(mut pagemap memory.Pagemap, base u64, length u64, change InheritChange) ? {
	end := base + length
	mut current := base
	for current < end {
		local_range, _, _ := addr2range(pagemap, current) or {
			errno.set(errno.enomem)
			return none
		}
		if local_range.immutable {
			errno.set(errno.eperm)
			return none
		}
		private := local_range.flags & map_shared == 0
		anonymous := local_range.flags & map_anonymous != 0
		if (change.need_private_anonymous && !(private && anonymous))
			|| (change.need_private && !private) || (change.need_shared && private) {
			errno.set(errno.einval)
			return none
		}
		current = local_range.base + local_range.length
	}

	current = base
	for current < end {
		mut local_range, _, _ := addr2range(pagemap, current) or { return }
		local_end := local_range.base + local_range.length
		snip_begin := current
		snip_end := if local_end < end { local_end } else { end }
		current = snip_end

		dont_fork := if change.set_dont_fork { change.dont_fork } else { local_range.dont_fork }
		wipe_on_fork := if change.set_wipe_on_fork {
			change.wipe_on_fork
		} else {
			local_range.wipe_on_fork
		}
		if dont_fork == local_range.dont_fork && wipe_on_fork == local_range.wipe_on_fork {
			continue
		}

		if snip_begin > local_range.base && snip_end < local_end {
			mut postsplit_range := new_local_range(MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: local_end - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			})?
			split_off_unlocked(mut pagemap, local_range, postsplit_range)
		}

		snip_size := snip_end - snip_begin
		if snip_size == local_range.length {
			local_range.dont_fork = dont_fork
			local_range.wipe_on_fork = wipe_on_fork
			continue
		}
		mut changed_range := new_local_range(MmapRangeLocal{
			pagemap: local_range.pagemap
			base: snip_begin
			length: snip_size
			offset: local_range.offset + i64(snip_begin - local_range.base)
			prot: local_range.prot
			flags: local_range.flags
			cow: local_range.cow
			immutable: local_range.immutable
			dont_fork: dont_fork
			wipe_on_fork: wipe_on_fork
			global: local_range.global
		})?
		split_off_unlocked(mut pagemap, local_range, changed_range)
	}
}

fn set_inheritance(mut pagemap memory.Pagemap, address u64, length u64, change InheritChange) ? {
	if address % page_size != 0 {
		errno.set(errno.einval)
		return none
	}
	if length == 0 {
		return
	}
	aligned := (length + page_size - 1) & ~(page_size - 1)
	if aligned < length || address >= memory.user_address_limit()
		|| aligned > memory.user_address_limit() - address {
		errno.set(errno.enomem)
		return none
	}
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	set_inheritance_unlocked(mut pagemap, address, aligned, change)?
}

// madvise(2)'s MADV_DONTFORK, MADV_DOFORK, MADV_WIPEONFORK and
// MADV_KEEPONFORK.
fn madvise_inheritance(address u64, length u64, advice int) (u64, u64) {
	mut pagemap := proc.current_thread().process.pagemap
	set_inheritance(mut pagemap, address, length, inherit_change_for_advice(advice)) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

// OpenBSD's minherit(2). SHARE and COPY are what a shared and a private
// mapping do anyway, and are only accepted for those.
pub fn syscall_minherit(_ voidptr, addr voidptr, length u64, inherit int) (u64, u64) {
	change := match inherit {
		map_inherit_none { InheritChange{
				set_dont_fork: true
				dont_fork: true
				set_wipe_on_fork: true
				wipe_on_fork: false
			} }
		map_inherit_zero { InheritChange{
				set_dont_fork: true
				dont_fork: false
				set_wipe_on_fork: true
				wipe_on_fork: true
				need_private_anonymous: true
			} }
		map_inherit_copy { InheritChange{
				set_dont_fork: true
				set_wipe_on_fork: true
				need_private: true
			} }
		map_inherit_share { InheritChange{
				set_dont_fork: true
				set_wipe_on_fork: true
				need_shared: true
			} }
		else { return errno.err, errno.einval }
	}
	mut pagemap := proc.current_thread().process.pagemap
	set_inheritance(mut pagemap, u64(addr), length, change) or { return errno.err, errno.get() }
	return 0, 0
}
