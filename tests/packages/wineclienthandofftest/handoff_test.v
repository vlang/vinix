// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.wineadapter

fn test_unsupported_client_handoff_refuses_without_consumption() {
	$if !linux {
		mut connection := wineadapter.ServerConnection{}
		directory := wineadapter.ServerDirectory{}
		guard := wineadapter.LaunchGuard{}
		mut client := connection.start_client(&directory, &guard, '/missing', wineadapter.ServerCommand{program: '/missing'}, []) or {
			if !err.msg().contains('requires Linux') || connection.descriptor() != -1 { panic('unexpected unsupported handoff result') }
			unsafe { err.free() }
			return
		}
		client.terminate() or { unsafe { err.free() } }
		panic('unsupported platform accepted client handoff')
	}
}

fn test_unsupported_client_cwd_refuses_without_consumption() {
	$if !linux {
		mut connection := wineadapter.ServerConnection{}
		directory := wineadapter.ServerDirectory{}
		guard := wineadapter.LaunchGuard{}
		mut client := connection.start_client_in(&directory, &guard, '/missing', wineadapter.ServerCommand{program: '/missing'}, [], -1) or {
			if !err.msg().contains('requires Linux') || connection.descriptor() != -1 { panic('unexpected unsupported cwd handoff result') }
			unsafe { err.free() }
			return
		}
		client.terminate() or { unsafe { err.free() } }
		panic('unsupported platform accepted client cwd handoff')
	}
}
