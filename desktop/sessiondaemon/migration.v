// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessioncore
import desktop.sessionipc
import os

// Migrate only the built-in legacy clock invocation. Preserve custom services,
// clock enable/restart choices and server arguments; publish on the next edit.
fn (mut daemon SessionDaemon) migrate_clock_service() {
	for i in 0 .. daemon.supervisor.count {
		mut service := &daemon.supervisor.services[i]
		if service.name.str() != 'clock-sync' || service.argument_count == 0
			|| service.arguments[0].str() != '--time-service' {
			continue
		}
		name := os.file_name(service.executable.str())
		legacy := name in ['vinix-desktop', 'vinix-desktop-gpu', 'vinix-desktop-system']
		unsafe { name.free() }
		if !legacy { continue }
		path := sessionipc.helper_path('vinix-timesync')
		service.executable.set(path) or {
			unsafe { path.free() }
			continue
		}
		unsafe { path.free() }
		for a in 1 .. service.argument_count { service.arguments[a - 1] = service.arguments[a] }
		service.argument_count--
		service.arguments[service.argument_count] = sessioncore.Text{}
	}
}
