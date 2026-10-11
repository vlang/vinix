// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os

fn main() {
	work := hosttest.work_dir('', 'vinix-policy-guest-build-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for arch in ['aarch64', 'x86_64'] {
		for family in ['tracker', 'print', 'diagnostic', 'hooks'] {
			for prod in if family == 'print' { [false, true] } else { [false] } {
				state := work + '/' + arch + '-' + family + '-' + prod.str()
				os.mkdir(state) or { panic(err) }
				init := guesthost.build_policy_guest(state, arch, family, prod, '') or { panic(err) }
				bytes := os.read_bytes(init) or { panic(err) }
				assert bytes.len > 20 && bytes[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
				assert int(bytes[18]) + (int(bytes[19]) << 8) == if arch == 'aarch64' { 183 } else { 62 }
				println('BUILT ' + arch + ' ' + family + ' production=' + prod.str())
			}
		}
	}
	println('Native independent policy guest builds: PASS')
}
