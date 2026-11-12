// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tests.packages.wineguardfixture

fn test_wine_launch_guard() {
	root := os.real_path(os.temp_dir()) + '/vinix-launch-guard-' + os.getpid().str()
	defer { unsafe { root.free() } }
	wineguardfixture.run(root, '')!
}
