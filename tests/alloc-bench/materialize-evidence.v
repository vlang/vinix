// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module main

import evidencearchive as archive
import os

fn fail(message string) {
	eprintln('usage: materialize-evidence {verify,read,materialize} ...')
	eprintln('materialize-evidence: error: ' + message)
	exit(2)
}

fn run(root string, args []string) ! {
	if args.len == 0 { fail('an action is required') }
	for arg in args {
		if arg == '--' { break }
		if arg in ['-h', '--help'] {
			println('usage: materialize-evidence {verify,read,materialize} ...\n\nVerify or recover byte-exact historical allocation benchmark source evidence.\nRecovery writes outside the checkout and never executes archived scripts.')
			return
		}
	}
	match args[0] {
		'verify' {
			if args.len != 1 && !(args.len == 2 && args[1] == '--') {
				fail('verify takes no arguments')
			}
			archive.verify(root, archive.manifest(root)!)!
		}
		'read' {
			paths := if args.len > 1 && args[1] == '--' { args[2..] } else { args[1..] }
			if paths.len != 1 { fail('read requires one evidence path') }
			if args.len > 1 && args[1] != '--' && paths[0].starts_with('-') {
				fail('unrecognized arguments: ' + paths[0])
			}
			content := archive.read_source(root, paths[0])!
			mut out := os.stdout()
			out.write_string(content)!
			out.flush()
		}
		'materialize' {
			mut output := ''
			mut output_provided := false
			mut paths := []string{}
			mut snapshot := ''
			mut index := 1
			for index < args.len {
				arg := args[index]
				index++
				if arg in ['-h', '--help'] {
					println('usage: materialize-evidence materialize --output OUTPUT [--path PATH ... | --snapshot CAMPAIGN]')
					return
				}
				spelling := arg.all_before('=')
				matches := ['--output', '--path', '--snapshot'].filter(it.starts_with(spelling))
				if !arg.starts_with('--') || matches.len != 1 {
					fail('unrecognized arguments: ' + arg)
				}
				option := matches[0]
				mut value := ''
				if arg.contains('=') {
					value = arg.all_after('=')
				} else {
					if index >= args.len || args[index].starts_with('--') {
						fail(option + ': expected one argument')
					}
					value = args[index]
					index++
				}
				match option {
					'--output' {
						output = if value == '' { '.' } else { value }
						output_provided = true
					}
					'--path' { paths << value }
					else {
						if value !in archive.campaigns {
							fail('invalid snapshot selection: ' + value)
						}
						snapshot = value
					}
				}
			}
			if !output_provided { fail('--output is required') }
			if snapshot != '' && (snapshot !in archive.campaigns || paths.len > 0) {
				fail('invalid or mutually exclusive snapshot selection')
			}
			archive.materialize(root, archive.manifest(root)!, output, paths, snapshot)!
		}
		else { fail('invalid action: ' + args[0]) }
	}
}

fn main() {
	guard := archive.own_commands()
	defer { guard.close() }
	run(os.real_path(os.dir(@FILE) + '/../..'), os.args[1..]) or {
		eprintln('Cannot recover historical source evidence: ${err}')
		exit(if err.code() in [130, 143] { err.code() } else { 1 })
	}
}
