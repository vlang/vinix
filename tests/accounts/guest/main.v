// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The guest half of the account tests: /sbin/init of a machine whose root
// file system holds the account tools and nothing else.
//
// The controller puts the name of one scenario in /etc/hwtest-scenario.
// This program runs it and reports on the serial port, in the lines the
// hardware tests use (tests/hardware-platform/guest/main.v).
//
// The same binary is also what the scenarios run *as an account* to see
// what that account can do: `/sbin/init probe <what>` (probe.v). Nothing in
// the image is a shell.
module main

import os

fn main() {
	if os.args.len > 1 && os.args[1] == 'package-signing-probe' {
		qualify_package_signing() or { eprintln(err); exit(1) }
		exit(0)
	}
	if os.args.len > 1 && os.args[1] == '--uid' { exit(package_sandbox_handoff_probe()) }
	if os.args.len > 1 && os.args[1] == 'package-probe' { exit(package_application_probe()) }
	if os.args.len > 1 && os.args[1] == 'package-policy-probe' { exit(package_policy_probe()) }
	if os.args.len > 1 && os.args[1] == 'package-context-probe' { exit(package_context_probe() or { eprintln(err); 89 }) }
	if os.args.len == 3 && os.args[1] == 'package-collection-limit-probe' {
		exit(package_collection_limit_probe(os.args[2]) or { eprintln(err); 89 })
	}
	if os.args.len > 1 && os.args[1] == 'probe' {
		exit(run_probe(os.args[2..]))
	}
	if os.args.len > 1 && os.args[1] == '-l' {
		// Started as someone's login shell.
		exit(run_probe(['ids']))
	}
	mut t := new_test()
	name := read_text('/etc/hwtest-scenario').trim_space()
	t.scenario = if name == '' { 'unknown' } else { name }
	t.say('HWTEST START ${t.scenario}')
	// Root's home is root's alone on a real system; the test image's tar
	// made it like every other directory.
	os.chmod('/root', 0o700) or {}
	match name {
		'accounts' { scenario_accounts(mut t) }
		'packages' { scenario_packages(mut t) }
		'packages-enforced' { scenario_packages_enforced(mut t) }
		'packages-linux' { scenario_packages_linux(mut t) }
		'packages-sqlite' { scenario_packages_sqlite(mut t) }
		'packages-ffmpeg' { scenario_packages_ffmpeg(mut t) }
		'packages-composition' { scenario_packages_composition(mut t) }
		'packages-context' { scenario_packages_context(mut t) }
		'packages-window' { scenario_packages_window(mut t) }
		'packages-window-input' { scenario_packages_window_input(mut t) }
		'packages-crash-staged', 'packages-crash-published', 'packages-crash-activated' {
			scenario_package_recovery(mut t)
		}
		'elevation' { scenario_elevation(mut t) }
		'unprivileged' { scenario_unprivileged(mut t) }
		'seat' { scenario_seat(mut t) }
		'sessions' { scenario_sessions(mut t) }
		'audit' { scenario_audit(mut t) }
		'keyring' { scenario_keyring(mut t) }
		else { t.check(false, 'the guest program has no scenario of this name') }
	}
	t.finish()
}
