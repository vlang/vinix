// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import proc
import lib

// Borrow each comma-delimited option rather than allocating a split list.
fn mount_option_present(options string, wanted string) bool {
	mut start := 0
	for start < options.len {
		mut end := start
		for end < options.len && options[end] != `,` { end++ }
		option := unsafe { tos(options.str + start, end - start) }
		if option == wanted { return true }
		start = end + 1
	}
	return false
}

// wxallowed belongs to the mount's current flags; an older filesystem
// options string must not advertise it after a remount has revoked it.
fn add_superblock_options(mut text lib.Text, options string) {
	if options == 'bind' { return }
	mut start := 0
	for start < options.len {
		mut end := start
		for end < options.len && options[end] != `,` { end++ }
		option := unsafe { tos(options.str + start, end - start) }
		if option.len > 0 && option != 'wxallowed' {
			text.add_byte(`,`)
			text.add(option)
		}
		start = end + 1
	}
}

// An environment request alone cannot disable W^X. The administrator may
// authorize a launcher, or the mount carrying the requested executable.
pub fn wx_exec_allowed(identity voidptr) bool {
	current := proc.current_thread()
	if current != unsafe { nil } {
		process := current.process
		if process.euid == 0 && proc.is_initial_namespace(process.ns.user)
			&& proc.has_capability(process, proc.cap_sys_admin) {
			return true
		}
	}
	return mount_flags(identity) & ms_wxallowed != 0
}
