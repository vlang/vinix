// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import perfrunner

fn main() {
	if os.args.len < 3 {
		eprintln('run-saved PROFILE SNAPSHOT-DIRECTORY NAME=BINARY...')
		exit(2)
	}
	root := os.real_path(@DIR + '/../..')
	suffix := match os.args[1] {
		'v4' { 'v4-final' }
		'final' { 'v3' }
		'v5' { 'v5-final' }
		'v6' { 'v6-final' }
		else {
			eprintln('unknown saved runner profile')
			exit(2)
		}
	}
	exit(perfrunner.cli(os.args[3..], root, os.args[2], root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-' + suffix))
}
