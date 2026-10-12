// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import steamshim

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	name := os.file_name(os.args[0])
	status := if name == 'lsof' {
		steamshim.lsof_cli(os.args[1..]) or {
			eprintln(err)
			1
		}
	} else {
		steamshim.tar_cli(os.args[1..]) or {
			eprintln(err)
			1
		}
	}
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { status })
}
