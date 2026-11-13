// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

// A fresh, independent writable variable store for each boot. APFS clones
// share unchanged extents, never the mutable file identity or subsequent writes.
fn copy_firmware_variables(source string, target string) ! {
	if os.exists(target) || os.is_link(target) { return error('firmware variable target already exists') }
	$if macos { return clone_firmware_variables(source, target) }
	$else { return os.cp(source, target) }
}
