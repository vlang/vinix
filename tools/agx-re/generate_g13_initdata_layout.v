// SPDX-License-Identifier: GPL-2.0-or-later
module main

import g13layout
import os

fn main() {
	mut raw_rs := g13layout.default_raw_rs()
	mut output := g13layout.default_output()
	mut check := false
	mut report := false
	mut stdout := false
	mut index := 1
	for index < os.args.len {
		argument := os.args[index]
		match argument {
			'--raw-rs', '--output' {
				index++
				if index == os.args.len {
					eprintln('${argument}: expected one argument')
					exit(2)
				}
				if argument == '--raw-rs' {
					raw_rs = os.args[index]
				} else {
					output = os.args[index]
				}
			}
			'--check' { check = true }
			'--report' { report = true }
			'--stdout' { stdout = true }
			'-h', '--help' {
				println('Compute the G13 InitData layout at each firmware ABI from m1n1 definitions.\n\nOptions:\n  --raw-rs PATH  versioned Rust definitions (VINIX_M1N1/rust/src/gpu/raw.rs)\n  --output PATH  generated kernel V constants\n  --check        fail if the generated file is stale\n  --report       print the per-field delta and added-field assignments\n  --stdout       print the generated source')
				return
			}
			else {
				if argument.starts_with('--raw-rs=') {
					raw_rs = argument.all_after('=')
				} else if argument.starts_with('--output=') {
					output = argument.all_after('=')
				} else {
					eprintln('unrecognized argument: ${argument}')
					exit(2)
				}
			}
		}
		index++
	}
	if report {
		println(g13layout.report(raw_rs) or {
			eprintln(err)
			exit(1)
		})
		println('')
		println(g13layout.classify_additions(raw_rs) or {
			eprintln(err)
			exit(1)
		})
		return
	}
	source := g13layout.generate(raw_rs) or {
		eprintln(err)
		exit(1)
	}
	if check {
		if !os.exists(output) || (os.read_file(output) or { '' }) != source {
			eprintln('stale generated G13 InitData layout: ${output}')
			exit(1)
		}
	} else if stdout {
		print(source)
	} else {
		os.write_file(output, source) or {
			eprintln(err)
			exit(1)
		}
	}
}
