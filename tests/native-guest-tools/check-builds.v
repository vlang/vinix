// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os

fn main() {
	work := hosttest.work_dir('', 'vinix-native-guest-build-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for arch in ['aarch64', 'x86_64'] {
		for suite in ['hypervisor', 'kernel-resources', 'amd64-console', 'application-sandbox', 'security-audit'] {
			if suite == 'amd64-console' && arch != 'x86_64' { continue }
			state := work + '/' + suite + '-' + arch
			os.mkdir(state) or { panic(err) }
			source := guesthost.root() + '/tests/' + suite + if suite == 'kernel-resources' {
				'/guest.c'
			} else if suite == 'security-audit' {
				'/collectorguestfixture/core.v'
			} else {
				'/guestfixture/core.v'
			}
			init := guesthost.compile_init(source, state, arch, suite == 'kernel-resources') or { panic(err) }
			bytes := os.read_bytes(init) or { panic(err) }
			assert bytes.len > 20 && bytes[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
			assert int(bytes[18]) + (int(bytes[19]) << 8) == if arch == 'aarch64' {
				183
			} else {
				62
			}
			println('BUILT ' + suite + ' ' + arch)
		}
	}
	println('Native guest init compiler/ELF profiles: PASS')
}
