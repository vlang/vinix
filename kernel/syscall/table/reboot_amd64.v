// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

import errno
import pagecache
import security
import uacpi

// reboot(magic1, magic2, command, arg) for amd64: the same checks as arm64's
// storage_reboot(), with ACPI where arm64 has PSCI. The desktop's power menu
// ends in this call.
fn syscall_linux_reboot(_ voidptr, magic1 u32, magic2 u32, command u32, _arg voidptr) (u64, u64) {
	if !security.permitted(security.system_reboot) {
		return errno.err, errno.eperm
	}
	if magic1 != 0xfee1dead || (magic2 != 0x28121969 && magic2 != 0x05121996
		&& magic2 != 0x16041998 && magic2 != 0x20112000) {
		return errno.err, errno.einval
	}
	if command != 0x01234567 && command != 0xcdef0123 && command != 0x4321fedc {
		return errno.err, errno.einval
	}
	// Nothing restarts a machine with unwritten data: a failed flush refuses
	// the transition rather than completing it.
	if !pagecache.sync_all() {
		return errno.err, errno.eio
	}
	if command == 0x01234567 {
		uacpi.reboot()
	} else {
		uacpi.power_off()
	}
	// A successful power transition does not return.
	return errno.err, errno.eio
}
