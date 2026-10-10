// SPDX-License-Identifier: GPL-2.0-or-later
module churncheck

import os

fn usage() string {
	return 'Usage: check-results LOG [--mode MODE] [--expect-flat-slabinfo] [--expect-flat-small]'
}

pub fn run(args []string) int {
	mut mode := 'exec'
	mut flat_slabinfo := false
	mut flat_small := false
	mut positional := false
	mut paths := []string{}
	mut cursor := 0
	for cursor < args.len {
		argument := args[cursor]
		cursor++
		if !positional {
			if argument == '--' {
				positional = true
				continue
			}
			if argument in ['-h', '--help'] {
				println(usage())
				println('Modes: ' + modes.join(', '))
				return 0
			}
			if argument.starts_with('--') {
				option := argument.all_before('=')
				matches := ['--mode', '--expect-flat-slabinfo', '--expect-flat-small'].filter(it.starts_with(option))
				if matches.len != 1 {
					eprintln(usage())
					return 2
				}
				if matches[0] == '--mode' {
					if argument.contains('=') {
						mode = argument.all_after('=')
					} else if cursor < args.len {
						mode = args[cursor]
						cursor++
					} else {
						eprintln(usage())
						return 2
					}
					if mode !in modes {
						eprintln('Unknown mode: ${mode}')
						return 2
					}
				} else {
					if argument.contains('=') {
						eprintln(usage())
						return 2
					}
					if matches[0] == '--expect-flat-slabinfo' {
						flat_slabinfo = true
					} else {
						flat_small = true
					}
				}
				continue
			}
			if argument.starts_with('-') && argument != '-' {
				eprintln(usage())
				return 2
			}
		}
		paths << argument
	}
	if paths.len != 1 {
		eprintln(usage())
		return 2
	}
	source := os.read_file(paths[0]) or {
		eprintln('FAIL: ${err}')
		return 1
	}
	report := inspect(source, mode, flat_slabinfo, flat_small) or {
		eprintln('FAIL: ${err}')
		return 1
	}
	print(report.output(flat_slabinfo))
	return 0
}
