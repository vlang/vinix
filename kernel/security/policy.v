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
pub const system_clock_set = 'system/clock/set'
pub const system_securelevel_set = 'system/securelevel/set'
pub const system_seat_set = 'system/seat/set'

// A selector has to be explicitly listed here. Unknown operations fail closed.
// Each operation requires an effective UID of zero and the Linux capability
// that guards it, so that a container whose runtime dropped CAP_SYS_ADMIN
// cannot mount or rename the machine even as root.
pub fn permitted(selector string) bool {
	allowed := permitted_now(selector)
	// Every one of these is rare and matters: who mounted, who set the
	// clock, who was refused.
	event(event_policy, !allowed, 0, selector)
	return allowed
}

fn permitted_now(selector string) bool {
	capability := match selector {
		filesystem_mount, filesystem_unmount, system_hostname_set, system_domainname_set,
		system_securelevel_set, system_seat_set {
			proc.cap_sys_admin
		}
		system_clock_set {
			proc.cap_sys_time
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
		// Only these selectors act on a namespace; every other one (clock,
		// reboot, securelevel, seat, and any added later) is host-wide.
		host_operation := match selector {
			system_hostname_set, system_domainname_set {
				proc.is_initial_namespace(process.ns.uts)
			}
			filesystem_mount, filesystem_unmount {
				proc.is_initial_namespace(proc.mount_namespace_of(process))
			}
			else { true }
		}
		if host_operation { return false }
		// The namespace this changes must belong to the caller's user
		// namespace, where its capabilities are real (Linux ns_capable). A
		// child user namespace keeps the creator's uid, so no euid test.
		owner := match selector {
			system_hostname_set, system_domainname_set { process.ns.uts.owner_user }
			else { proc.mount_namespace_of(process).owner_user }
		}
		return proc.has_namespace_capability(process, capability, owner)
	}
	return process.euid == 0 && proc.has_capability(process, capability)
}
