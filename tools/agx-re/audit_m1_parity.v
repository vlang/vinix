// SPDX-License-Identifier: GPL-2.0-or-later
import g13layout
import m1parity
import os

fn run() !int {
	mut options := {
		'--vinix': g13layout.repo_root()
		'--m1n1':  g13layout.default_m1n1()
	}
	mut index := 1
	for index < os.args.len {
		key := os.args[index]
		if key == '--help' {
			println('Offline M1 source audit. No boot or GPU access.\nUsage: audit_m1_parity --asahi-linux PATH --packages PATH --omarchy PATH [--vinix PATH] [--m1n1 PATH] [--output FRESH_EXTERNAL_DIR]\nExit: 1 = parity not established, 2 = audit/provenance error. A partial source audit never certifies 100% parity.')
			return 0
		}
		if key !in ['--vinix', '--m1n1', '--asahi-linux', '--packages', '--omarchy', '--output']
			|| index + 1 >= os.args.len || os.args[index + 1].starts_with('--') {
			return error('expected a supported option and path; use --help')
		}
		options[key] = os.abs_path(os.args[index + 1])
		index += 2
	}
	for required in ['--asahi-linux', '--packages', '--omarchy'] {
		if required !in options { return error('missing ${required}; use --help') }
	}
	inputs := m1parity.Inputs{
		vinix:    options['--vinix']
		asahi:    options['--asahi-linux']
		packages: options['--packages']
		omarchy:  options['--omarchy']
		m1n1:     options['--m1n1']
	}
	report := m1parity.audit(inputs)!
	if directory := options['--output'] { m1parity.retain(inputs, report, directory)! }
	print(report.markdown())
	return report.exit_code()
}

fn main() {
	code := run() or {
		eprintln('M1 source audit failed: ${err}')
		exit(2)
	}
	exit(code)
}
