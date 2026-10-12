// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import guestvalidation
import validationhost

fn main() {
	if os.args.len >= 2 && os.args[1] == '--record-android' {
		status := validationhost.record_android(os.args[2..]) or {
			eprintln(err)
			exit(1)
		}
		exit(status)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 {
		eprintln('expected native validation command')
		exit(2)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	result := dispatch(root, os.args[1], os.args[2..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { result })
}

fn dispatch(root string, name string, argv []string) !int {
	return match name {
		'download', 'download-cube', 'download-gow', 'download-nzp' {
			validationhost.download_cli(root, if name == 'download' {
				'ppsspp'
			} else {
				name.all_after('download-')
			}, argv)!
		}
		'qemu-dns' { guestvalidation.dns_cli(argv)! }
		'roblox-launcher' { validationhost.roblox_launcher_cli(root, argv)! }
		'codex-smoke', 'claude-smoke' {
			guestvalidation.smoke_cli(root, argv, name == 'claude-smoke')!
		}
		'x-window-check' { guestvalidation.xwindow_cli(argv)! }
		'gpu-present' { validationhost.gpu_cli(root, argv)! }
		else { return error_with_code('unknown native validation command: ' + name, 2) }
	}
}
