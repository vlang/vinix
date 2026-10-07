// SPDX-License-Identifier: GPL-2.0-or-later
module main

import g13contract
import g13layout
import os

fn main() {
	mut m1n1 := g13layout.default_m1n1()
	mut asahi := ''
	mut asahi_provided := false
	mut index := 1
	for index < os.args.len {
		argument := os.args[index]
		match argument {
			'--m1n1', '--asahi-linux' {
				index++
				if index == os.args.len || option_like(os.args[index]) {
					eprintln('${argument}: expected one argument')
					exit(2)
				}
				if argument == '--m1n1' {
					m1n1 = os.args[index]
				} else {
					asahi = os.args[index]
					asahi_provided = true
				}
			}
			'-h', '--help' {
				println('Check the G13 firmware contract against local m1n1/Asahi sources.\n\nOptions:\n  --m1n1 PATH        m1n1 reference checkout (VINIX_M1N1)\n  --asahi-linux PATH optional Asahi Linux checkout')
				return
			}
			else {
				if argument.starts_with('--m1n1=') {
					m1n1 = argument.all_after('=')
				} else if argument.starts_with('--asahi-linux=') {
					asahi = argument.all_after('=')
					asahi_provided = true
				} else {
					eprintln('unrecognized argument: ${argument}')
					exit(2)
				}
			}
		}
		index++
	}
	results := g13contract.check_m1n1(m1n1) or {
		eprintln('G13 reference contract failed: ${err}')
		exit(1)
	}
	println('m1n1 ${g13contract.git_revision(m1n1)}:')
	for result in results { println('  ok  ${result}') }
	if asahi_provided {
		asahi_results := g13contract.check_asahi(asahi) or {
			eprintln('G13 reference contract failed: ${err}')
			exit(1)
		}
		println('Asahi Linux ${g13contract.git_revision(asahi)}:')
		for result in asahi_results { println('  ok  ${result}') }
	} else {
		println('Asahi Linux: skipped (pass --asahi-linux to check a checkout)')
	}
}

fn option_like(text string) bool {
	return text.len > 1 && text[0] == `-` && !text[1].is_digit() && text[1] != `.`
}
