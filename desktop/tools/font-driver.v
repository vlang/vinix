// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import fontkit
import os

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 || os.args[1] !in ['generate', 'test'] {
		eprintln('expected generate|test')
		exit(2)
	}
	if os.args[1] == 'generate' {
		args := cachecli.arguments(os.args[2..], ['--japanese-source', '--output', '--japanese-font-dir',
			'--cache'], [], ['--update-japanese-subsets'], 0, 0,
			'Rasterise Roboto with Chinese and Japanese fallback into V source.\nUsage: genfont [--update-japanese-subsets] [--japanese-source TTF]\n               [--output FILE] [--japanese-font-dir DIR] [--cache DIR]') or {
			eprintln(err)
			exit(2)
		}
		if '--japanese-source' in args.options && '--update-japanese-subsets' !in args.options {
			eprintln('--japanese-source requires --update-japanese-subsets')
			exit(2)
		}
	}
	source := os.dir(@FILE) + '/' + if os.args[1] == 'generate' {
		'genfont.v'
	} else {
		'tests/test_font_data.v'
	}
	status := fontkit.run(source, os.args[2..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 })
	}
	exit(status)
}
