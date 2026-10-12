// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidrun
import androidtools
import androidrunfixtures
import cachecli
import hosttest
import os

fn main() {
	if os.args.len == 2 && os.args[1] == '--mock-vm' {
		androidrunfixtures.mock_vm() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 {
		eprintln('usage: android-run run|input|roblox-build [arguments]')
		exit(2)
	}
	root := hosttest.root()
	status := match os.args[1] {
		'run' {
			androidrun.run_cli(root, os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'input' {
			androidrun.input_cli(os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'roblox-build' {
			androidrun.roblox_cli(root, os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'screenshot' {
			androidrun.screenshot_cli(os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'interactive-tests' {
			androidrunfixtures.interactive_cli(root, os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'roblox-tests' {
			androidrunfixtures.roblox_tests(root, os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'desktop-check-android', 'desktop-check-roblox' {
			androidrun.preflight_cli(root, os.args[1], os.args[2..]) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		'art-runtime', 'musl-runtime' {
			androidrun.runtime_api(os.args[2..], if os.args[1] == 'musl-runtime' {
				'musl'
			} else {
				'art'
			}) or {
				eprintln(err.msg())
				exit(androidtools.failure_status(err))
			}
		}
		else {
			eprintln('unknown native Android runner command: ' + os.args[1])
			exit(2)
		}
	}
	exit(status)
}
