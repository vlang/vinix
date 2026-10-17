// SPDX-License-Identifier: GPL-2.0-or-later
// Native substitutes for build commands in the isolated compatibility test.
module main

import os

fn main() {
	name := os.base(os.args[0])
	if os.getenv('VINIX_LIMINE_FAIL') == name {
		eprintln('forced Limine fixture failure: ' + name)
		exit(37)
	}
	match name {
		'configure' {
			os.write_file('GNUmakefile', '')!
		}
		'llvm-objcopy' {}
		'sysctl' { println('2') }
		'make' {
			if os.read_file('common/protos/limine.c')!.contains('Base revision %u is no longer supported for aarch64') {
				exit(91)
			}
			os.mkdir_all('bin')!
			os.write_file('bin/BOOTAA64.EFI', 'Limine 12.9.3 (aarch64, UEFI)\n')!
		}
		'curl' {
			eprintln('unexpected download in the isolated Limine fixture')
			exit(92)
		}
		else {
			eprintln('unknown Limine fixture command: ' + name)
			exit(93)
		}
	}
}
