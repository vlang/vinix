// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_readiness_refuses() {
	$if !linux {
		mut child := wineadapter.ServerChild{}
		server := wineadapter.ServerDirectory{}
		guard := wineadapter.LaunchGuard{}
		mut connection := child.await_connection(&server, &guard, '/missing', 100) or {
			assert err.msg().contains('requires Linux')
			assert child.process_id() == 0
			unsafe { err.free() }
			return
		}
		connection.close()
		panic('unsupported platform accepted readiness')
	}
}
