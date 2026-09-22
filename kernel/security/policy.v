// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module security

import proc

// Stable names for privileged operations. Keep authorization at the syscall
// boundary, before touching userspace pointers or changing global state.
pub const filesystem_mount = 'filesystem/mount'
pub const filesystem_unmount = 'filesystem/unmount'
pub const system_hostname_set = 'system/hostname/set'
pub const system_domainname_set = 'system/domainname/set'
pub const system_reboot = 'system/reboot'

// A selector has to be explicitly listed here. Unknown operations fail closed.
// Vinix does not have fine-grained capabilities yet, so these operations
// currently require an effective UID of zero.
pub fn permitted(selector string) bool {
	if selector != filesystem_mount && selector != filesystem_unmount
		&& selector != system_hostname_set && selector != system_domainname_set
		&& selector != system_reboot {
		return false
	}
	return proc.current_thread().process.euid == 0
}
