// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_child_refuses() {
	$if !linux {
		directory := wineadapter.ServerDirectory{}
		guard := wineadapter.LaunchGuard{}
		mut owned := directory.start_child(&guard, '/missing', wineadapter.ServerCommand{program: '/missing'}) or {
			assert err.msg().contains('requires Linux')
			unsafe { err.free() }
			return
		}
		owned.terminate() or { unsafe { err.free() } }
		panic('unsupported platform accepted server child')
	}
}

fn test_empty_child_has_no_pid() {
	owned := wineadapter.ServerChild{}
	assert owned.process_id() == 0
}
