// SPDX-License-Identifier: GPL-2.0-or-later
module fs

// Raw options include a password. Neither initial mounts nor remounts may
// preserve them in permanent mount records or publish them through procfs.
fn (_ &SMB2FS) mount_options_private() bool {
	return true
}
