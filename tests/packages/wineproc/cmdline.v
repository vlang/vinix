// SPDX-License-Identifier: GPL-2.0-or-later
module wineproc

import os

// Disappearance during enumeration is normal. An unreadable surviving entry
// cannot establish absence of a live Wine client.
pub fn command_line(directory string) !string {
	return os.read_file(directory + '/cmdline') or {
		if !os.exists(directory) { return '' }
		return error('cannot inspect surviving process command line: ' + directory)
	}
}
