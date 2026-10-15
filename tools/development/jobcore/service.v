// SPDX-License-Identifier: GPL-2.0-or-later
module jobcore

import desktop.sessioncore
import os

fn unit_argument(value string) !string {
	// The native importer refuses dollar/percent expansions. Keep exported
	// argv literal in its supported unit subset.
	if !value.starts_with('/') || value.contains_any('$%')
		|| value.bytes().any(it < 32 || it == 127) {
		return error('service paths must be absolute without control bytes, dollar or percent signs')
	}
	return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
}

// Export only. Installation and enablement remain with the account's existing
// service manager; no credential values or job environment enter this unit.
pub fn service_unit(path string) !string {
	load(path)!
	state := unit_argument(os.real_path(path))!
	executable := unit_argument(os.real_path(os.executable()))!
	unit := '[Unit]\nDescription=Vinix scheduled jobs\n[Service]\nType=simple\n' +
		'ExecStart=' + executable + ' watch ' + state + '\n' +
		'Restart=on-failure\nRestartSec=1s\nTimeoutStopSec=10s\n' +
		'[Install]\nWantedBy=default.target\n'
	// Validate against the maintained native contract, including its bounded
	// arguments. The stop window exceeds the scheduler's eight-second grace.
	service := sessioncore.import_linux_service('vinix-jobs.service', unit, false)!
	mut supervisor := sessioncore.Supervisor{count: 1}
	supervisor.services[0] = service
	supervisor.validate()!
	return unit
}
