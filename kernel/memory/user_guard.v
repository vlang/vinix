// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module memory

// Supervisor-mode access prevention: SMAP on amd64, PAN on arm64. While the
// bit is set, the CPU faults when the kernel touches a page userspace can
// reach, so a kernel bug that follows a pointer userspace chose -- a null
// function table, a corrupted object -- cannot be steered at memory the
// attacker prepared. OpenBSD has run with SMAP since 5.3.
//
// The kernel's own transfers do not go through user addresses at all:
// usercopy resolves each page and copies through the direct map. What the bit
// catches is a path that still dereferences a user pointer as it stands.
//
// vinix.user_access= on the kernel command line picks what happens then:
//   strict  the fault is a kernel fault, as on OpenBSD
//   audit   the access is let through, and the kernel address is logged once
//   off     the bit stays clear
// tests/user-access/sites.py names the paths an audit logged.
import katomic
import limine

pub const user_guard_off = 0
pub const user_guard_audit = 1
pub const user_guard_strict = 2

// What happens when the command line does not say. A debug kernel traces each
// syscall's path argument where the process has it, so it can only audit.
fn user_guard_default() int {
	$if prod {
		return user_guard_strict
	} $else {
		return user_guard_audit
	}
}

const user_guard_site_slots = 512

__global (
	user_guard_mode  = int(-1)
	// Whether the command line chose the mode.
	user_guard_asked = false
	user_guard_sites [512]u64
	user_guard_hits  u64
)

fn cmdline_option(name string) ?string {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return none
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	mut index := 0
	for unsafe { text[index] } != 0 {
		for unsafe { text[index] } == ` ` {
			index++
		}
		start := index
		for unsafe { text[index] } != 0 && unsafe { text[index] } != ` ` {
			index++
		}
		if index - start <= name.len {
			continue
		}
		mut matched := true
		for i in 0 .. name.len {
			if unsafe { text[start + i] } != name[i] {
				matched = false
				break
			}
		}
		if matched {
			return unsafe { tos(&text[start + name.len], index - start - name.len) }
		}
	}
	return none
}

// What the command line asked for. Read once, on the boot CPU, before any
// other CPU starts.
pub fn user_guard_requested() int {
	if user_guard_mode >= 0 {
		return user_guard_mode
	}
	mut mode := user_guard_default()
	if value := cmdline_option('vinix.user_access=') {
		if value == 'off' {
			mode = user_guard_off
			user_guard_asked = true
		} else if value == 'audit' {
			mode = user_guard_audit
			user_guard_asked = true
		} else if value == 'strict' {
			mode = user_guard_strict
			user_guard_asked = true
		}
	}
	user_guard_mode = mode
	return mode
}

// Leave the bit clear unless the command line asked for it: for a machine it
// has not been run on, where the first boot with it should be one somebody
// chose to make.
pub fn user_guard_untested() {
	if !user_guard_asked {
		user_guard_mode = user_guard_off
	}
}

// The CPU has no such bit: nothing is enforced and nothing reported.
pub fn user_guard_unsupported() {
	user_guard_mode = user_guard_off
}

pub fn user_guard_auditing() bool {
	return user_guard_mode == user_guard_audit
}

// Count a direct access the audit let through. True the first time `pc`, which
// the caller may have mixed with what called it, is seen: that is when the
// caller describes it in the log.
pub fn user_guard_note(pc u64) bool {
	katomic.inc(mut &user_guard_hits)
	for i in 0 .. user_guard_site_slots {
		seen := katomic.load(&user_guard_sites[i])
		if seen == pc {
			return false
		}
		if seen == 0 {
			if katomic.cas(mut &user_guard_sites[i], u64(0), pc) {
				return true
			}
			if katomic.load(&user_guard_sites[i]) == pc {
				return false
			}
		}
	}
	return false
}
