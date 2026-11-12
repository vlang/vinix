// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_endpoint_platform_refuses() {
	$if !linux {
		mut guard := wineadapter.LaunchGuard{}
		mut directory := wineadapter.ServerDirectory{}
		mut endpoint := directory.capture_endpoint(&guard, '/missing') or {
			assert err.msg().contains('requires Linux')
			unsafe { err.free() }
			return
		}
		endpoint.close(); directory.close(); guard.close()
		panic('unsupported endpoint capture accepted')
	}
}
