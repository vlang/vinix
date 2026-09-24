// SPDX-License-Identifier: GPL-2.0-or-later
module security

import proc

fn test_unknown_selector_fails_closed_even_for_root() {
	proc.set_test_euid(0)
	proc.set_test_caps(u64(-1))
	assert !permitted('filesystem/mount/other')
	assert !permitted('system/reboot/other')
	assert !permitted('')
}

fn test_known_selector_requires_effective_root() {
	for selector in [filesystem_mount, filesystem_unmount, system_hostname_set, system_domainname_set,
		system_reboot] {
		proc.set_test_caps(u64(-1))
		proc.set_test_euid(0)
		assert permitted(selector)
		proc.set_test_euid(1000)
		assert !permitted(selector)
	}
}

// A container's root keeps UID 0 but not the capabilities its runtime dropped.
fn test_root_without_the_guarding_capability_is_denied() {
	proc.set_test_euid(0)
	proc.set_test_caps(u64(-1) & ~(u64(1) << proc.cap_sys_admin))
	for selector in [filesystem_mount, filesystem_unmount, system_hostname_set,
		system_domainname_set] {
		assert !permitted(selector)
	}
	assert permitted(system_reboot)

	proc.set_test_caps(u64(-1) & ~(u64(1) << proc.cap_sys_boot))
	assert !permitted(system_reboot)
	assert permitted(filesystem_mount)
	proc.set_test_caps(u64(-1))
}
