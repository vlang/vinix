module main

import comparecore as benchmark
import os

const usage = 'usage: compare [-h] [--vinix-config VINIX_CONFIG] [--macos-config MACOS_CONFIG]\n               [--allow-mismatch] vinix_log macos_log'

fn fail(message string) {
	eprintln(usage)
	eprintln('compare: error: ' + message)
	exit(2)
}

fn main() {
	mut paths := []string{}
	mut configs := ['', '']
	mut config_provided := [false, false]
	mut diagnostic := false
	mut cursor := 1
	mut positional := false
	for cursor < os.args.len {
		arg := os.args[cursor]
		cursor++
		if !positional && arg in ['-h', '--help'] {
			println(usage + '\n\nValidate complete allocation benchmark logs and compare paired QEMU runs.\nMedians are recomputed from raw samples; unmatched diagnostics exit 2.')
			return
		}
		if !positional && arg == '--' {
			positional = true
			continue
		}
		if !positional && arg == '--allow-mismatch' {
			diagnostic = true
			continue
		}
		if !positional && arg.starts_with('--') {
			spelling := arg.all_before('=')
			matches := ['--vinix-config', '--macos-config', '--allow-mismatch', '--help'].filter(it.starts_with(spelling))
			option := if matches.len == 1 { matches[0] } else { spelling }
			if option in ['--allow-mismatch', '--help'] {
				if arg.contains('=') { fail('argument ${option}: ignored explicit argument') }
				if option == '--allow-mismatch' {
					diagnostic = true
					continue
				}
				println(usage + '\n\nValidate complete allocation benchmark logs and compare paired QEMU runs.\nMedians are recomputed from raw samples; unmatched diagnostics exit 2.')
				return
			}
			if option !in ['--vinix-config', '--macos-config'] {
				fail('unrecognized arguments: ' + arg)
			}
			mut value := ''
			if arg.contains('=') {
				value = arg.all_after('=')
			} else {
				if cursor >= os.args.len || (os.args[cursor].starts_with('-') && os.args[cursor].len > 1 && !os.args[cursor][1].is_digit() && os.args[cursor] != '-') {
					fail('argument ${option}: expected one argument')
				}
				value = os.args[cursor]
				cursor++
			}
			index := if option == '--vinix-config' { 0 } else { 1 }
			configs[index] = if value == '' { '.' } else { value }
			config_provided[index] = true
			continue
		}
		if !positional && arg.starts_with('-') && arg != '-' {
			fail('unrecognized arguments: ' + arg)
		}
		paths << arg
	}
	if paths.len != 2 { fail('two log paths are required') }
	for index, path in paths {
		if !config_provided[index] { configs[index] = os.join_path(os.dir(path), 'config.json') }
	}
	left := benchmark.read_run(paths[0], configs[0], 'Vinix') or {
		eprintln('Cannot compare: ${err}')
		exit(1)
	}
	right := benchmark.read_run(paths[1], configs[1], 'macOS') or {
		eprintln('Cannot compare: ${err}')
		exit(1)
	}
	mismatches, notes := benchmark.comparability(left, right)
	if mismatches.len > 0 && !diagnostic {
		eprintln('Cannot compare: runs are not comparable:\n' + mismatches.map('- ' + it).join('\n'))
		exit(1)
	}
	print(benchmark.render(left, right, mismatches, notes))
	if mismatches.len > 0 { exit(2) }
}
