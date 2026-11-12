// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_identity_platform_refuses() {
	$if !linux {
		mut refused := false
		wineadapter.verify_server_identity(3, 4, 123) or { refused = err.msg().contains('requires Linux'); unsafe { err.free() } }
		assert refused
	}
}
