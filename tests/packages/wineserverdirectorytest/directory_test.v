// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tests.packages.wineserverdirectoryfixture

fn test_private_server_directory() {
	root := os.real_path(os.temp_dir()) + '/vinix-server-directory-' + os.getpid().str()
	defer { unsafe { root.free() } }
	wineserverdirectoryfixture.run(root)!
}
