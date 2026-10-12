// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import os
import runtimefixtures

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	mut argv := []string{}
	for argument in os.args[1..] {
		if argument in ['-v', '-q'] { continue }
		argv << if argument == '-k' { '--filter' } else { argument }
	}
	args := cachecli.arguments(argv, ['--work', '--filter'], [], [], 0, 0, 'Offline Vulkan staging regressions.\nUsage: vulkan-stage-test [--work DIR --filter TEXT -k TEXT -v -q]') or {
		eprintln(err)
		exit(2)
	}
	work := args.value('--work', os.temp_dir() + '/vinix-vulkan-fixture-' + os.getpid().str())
	gamehost.mkdir(work) or { panic(err) }
	runtimefixtures.vulkan_cases(os.real_path(os.dir(@FILE) + '/../..'), work, args.value('--filter', '')) or {
		eprintln(err)
		exit(1)
	}
}
