// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Hardware and power tests: boot a kernel in QEMU with a V test program as
// its init, and judge what it prints. The controller is the hwhost module;
// README.md says what the suite covers and what it does not.
module main

import hwhost
import os

fn main() {
	// @FILE is where this source was when it was compiled, which is how the
	// controller finds the checkout: the binary itself is built in a
	// temporary directory.
	exit(hwhost.run(os.args[1..], @FILE))
}
