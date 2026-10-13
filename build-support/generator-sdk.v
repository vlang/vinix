// SPDX-License-Identifier: GPL-2.0-or-later
module main

import generatorsdk
import os

fn main() {
	if os.args[1..] == ['--help'] {
		println('Usage: generator-sdk qemu|virgl EXECUTABLE\nVerify a separately provisioned upstream generator SDK as filesystem data; never launch its interpreter.')
		return
	}
	if os.args.len != 3 { eprintln('expected qemu|virgl EXECUTABLE'); exit(2) }
	println(generatorsdk.verify(os.args[1], os.args[2]) or { eprintln(err); exit(1) })
}
