// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_connection_refuses() {
	$if !linux {
		mut endpoint := wineadapter.ServerEndpoint{}
		mut directory := wineadapter.ServerDirectory{}
		mut guard := wineadapter.LaunchGuard{}
		mut connection := endpoint.connect(&directory, &guard, '/missing', 123, 100) or {
			assert err.msg().contains('requires Linux')
			unsafe { err.free() }
			return
		}
		connection.close()
		panic('unsupported connection accepted')
	}
}
