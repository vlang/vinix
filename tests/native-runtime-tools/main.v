// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import runtimehost

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 {
		eprintln('expected native runtime command')
		exit(2)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	result := dispatch(root, os.args[1], os.args[2..]) or {
		eprintln(err.msg())
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
	exit(result)
}

fn dispatch(root string, name string, argv []string) !int {
	return match name {
		'debian-root' { runtimehost.debian_cli(root, argv)! }
		'prepare-debian' { runtimehost.prepare_debian_cli(root, argv)! }
		'dhewm-build' { runtimehost.doom_build_cli(root, argv)! }
		'dhewm-run' { runtimehost.doom_run_cli(root, argv)! }
		'mesa-build', 'venus-build' { runtimehost.driver_cli(root, argv, name == 'venus-build')! }
		'vulkan-stage' { runtimehost.vulkan_cli(root, argv)! }
		'vulkan-run' { runtimehost.vulkan_guest_cli(root, argv)! }
		'qemu-stage' { runtimehost.qemu_cli(root, argv)! }
		else { return error_with_code('unknown native runtime command: ' + name, 2) }
	}
}
