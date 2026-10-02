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
pub const system_securelevel_set = 'system/securelevel/set'

// A selector has to be explicitly listed here. Unknown operations fail closed.
// Each operation requires an effective UID of zero and the Linux capability
// that guards it, so that a container whose runtime dropped CAP_SYS_ADMIN
// cannot mount or rename the machine even as root.
pub fn permitted(selector string) bool {
	capability := match selector {
		filesystem_mount, filesystem_unmount, system_hostname_set, system_domainname_set,
		system_securelevel_set {
			proc.cap_sys_admin
		}
		system_reboot {
			proc.cap_sys_boot
		}
		else {
			return false
		}
	}
	if !proc.mac_trusted() { return false }
	process := proc.current_thread().process
	// Namespace-local capabilities do not authorize changes to host state.
	// Private mount and UTS namespaces retain their existing controls.
	if !proc.is_initial_namespace(process.ns.user) {
		host_operation := match selector {
			system_securelevel_set, system_reboot { true }
			system_hostname_set, system_domainname_set {
				proc.is_initial_namespace(process.ns.uts)
			}
			filesystem_mount, filesystem_unmount {
				proc.is_initial_namespace(proc.mount_namespace_of(process))
			}
			else { false }
		}
		if host_operation { return false }
	}
	return process.euid == 0 && proc.has_capability(process, capability)
}
