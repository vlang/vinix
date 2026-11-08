// SPDX-License-Identifier: GPL-2.0-or-later
// The compositor filters LD_PRELOAD. Restore it only in the diagnostic guest.
module main

import os

fn main() {
	os.setenv('LD_PRELOAD', '/usr/lib/libvox-trace.so', true)
	os.execvp('/usr/bin/vox-real', os.args[1..]) or { panic(err) }
}
