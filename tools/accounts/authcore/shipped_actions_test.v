// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module authcore

import os

// Every action file that ships must be one the service accepts, and must
// run a program this repository builds.
fn test_shipped_actions_parse() ! {
	directory := os.join_path(os.dir(@FILE), '..', 'actions')
	names := os.ls(directory)!
	assert names.len >= 10
	for name in names {
		action := parse_action(name, os.read_file(os.join_path(directory, name))!) or {
			assert false, '${name}: ${err.msg()}'
			continue
		}
		assert action.exec in ['/usr/sbin/vinix-system', '/usr/sbin/vinix-account', '/usr/bin/vinix-package', '/usr/sbin/vinix-session'], name
		if action.exec == '/usr/sbin/vinix-session' || action.auth == .account {
			assert name == 'packages-launch' && action.exec == '/usr/sbin/vinix-session' && action.auth == .account && action.args == ['package-launch'] && action.input && action.params.len == 0
		}
		if action.exec == '/usr/bin/vinix-package' {
			assert name == 'packages-change' && action.auth == .admin && action.args == ['admin-authorize'] && action.input && action.params.len == 0
		}
		// Nothing that changes accounts or the machine's name is open to
		// someone who merely sits at it.
		if action.exec == '/usr/sbin/vinix-account' || name == 'hostname-set' {
			assert action.auth == .admin, name
		}
	}
}
