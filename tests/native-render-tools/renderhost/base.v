// SPDX-License-Identifier: GPL-2.0-or-later
module renderhost

import cachecli
import sourcecommand

pub struct Tools {
pub:
	root         string
	command_hook fn ([]string, map[string]string, voidptr) !sourcecommand.Output = unsafe { nil }
	context      voidptr
}

pub fn (tools Tools) command(argv []string, environment map[string]string) !sourcecommand.Output {
	if tools.command_hook != unsafe { nil } {
		return tools.command_hook(argv, environment, tools.context)!
	}
	return sourcecommand.capture_full(argv, environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
}

pub fn (tools Tools) checked(argv []string, environment map[string]string) !string {
	r := tools.command(argv, environment)!
	if r.status != 0 || r.stdout.contains('retrying with') || r.stderr.contains('retrying with') {
		return error('render command failed: ' + argv.str() + '\n' + r.stdout + r.stderr)
	}
	return r.stdout
}

pub fn dispatch(root string, command string, argv []string) !int {
	tools := Tools{ root: root }
	return match command {
		'g17-host' { g17_host_cli(root, argv)! }
		'g17-native' { g17_native_cli(root, argv)! }
		'g17-vm' { g17_vm_cli(root, argv)! }
		'virgl-vm' { virgl_cli(tools, argv)! }
		'krandom' { krandom_cli(tools, argv)! }
		else { return error_with_code('unknown native render command: ' + command, 2) }
	}
}
