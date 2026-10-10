// SPDX-License-Identifier: GPL-2.0-or-later
module wifihost

import crypto.sha256
import hosttest
import os

fn parsed(args []string, options []hosttest.Option, count int, usage string, description string) hosttest.Arguments {
	return hosttest.parse_arguments(args, options, count, usage, description) or {
		eprintln(usage)
		eprintln(err)
		exit(2)
	}
}

pub fn run_package(args []string) {
	usage := 'usage: package --status STATUS --firmware FILE --nvram FILE --clm FILE --txcap FILE --output DIRECTORY'
	options := ['--status', '--firmware', '--nvram', '--clm', '--txcap', '--output'].map(hosttest.Option{it, true, []string{}})
	p := parsed(args, options, 0, usage, 'Package explicitly selected, locally extracted Apple firmware. The manifest binds the selection to a saved device status.')
	for option in options {
		if option.name !in p.options {
			eprintln(usage)
			eprintln('required argument: ' + option.name)
			exit(2)
		}
	}
	a := PackageOptions{p.options['--status'], p.options['--firmware'], p.options['--nvram'], p.options['--clm'], p.options['--txcap'], p.options['--output']}
	package(a) or {
		eprintln(err)
		exit(if err is SelectionError { 2 } else { 1 })
	}
	println('Wrote ${path_value(a.output)}; selected firmware must match this machine’s board/module.')
}

pub fn run_generator(args []string, control bool) {
	usage := if control {
		'usage: compile-v OUTPUT [--arch arm64|amd64]'
	} else {
		'usage: compile-provider OUTPUT [--kind protocol|platform] [--arch arm64|amd64]'
	}
	mut options := [hosttest.Option{'--arch', true, ['arm64', 'amd64']}]
	if !control { options << hosttest.Option{'--kind', true, ['protocol', 'platform']} }
	p := parsed(args, options, 1, usage, 'Emit the maintained native V Wi-Fi code with its original target and platform hooks.')
	kind := if control { 'control' } else { p.options['--kind'] or { 'protocol' } }
	output := if control {
		path_value(p.positional[0])
	} else {
		hosttest.module_resolve(p.positional[0]) or {
			eprintln(err)
			exit(1)
		}
	}
	generate(kind, output, p.options['--arch'] or { 'arm64' }) or {
		eprintln(err)
		exit(1)
	}
}

pub fn run_verifier(args []string, testing bool) {
	usage := if testing {
		'usage: verify-test KERNEL GENERATED_C'
	} else {
		'usage: verify-build KERNEL GENERATED_C'
	}
	p := parsed(args, []hosttest.Option{}, 2, usage, 'Verify the linked AArch64 kernel and generated Wi-Fi initialization and polling call sites.')
	data := os.read_bytes(p.positional[0]) or {
		eprintln('FAIL: ' + err.msg())
		exit(1)
	}
	source := hosttest.module_read_text(p.positional[1]) or {
		eprintln('FAIL: ' + err.msg())
		exit(1)
	}
	if testing {
		verify_regressions(data, source) or {
			eprintln('FAIL: ' + err.msg())
			exit(1)
		}
		println('PASS 11 build-verifier regression groups against the linked kernel')
		return
	}
	names := elf_symbols(data) or {
		eprintln('FAIL: ' + err.msg())
		exit(1)
	}
	verify_hooks(source) or {
		eprintln('FAIL: ' + err.msg())
		exit(1)
	}
	println('PASS linked AArch64 static kernel; ${required_symbols.len} required Wi-Fi symbols; ${names.len} defined symbols')
	println('PASS initialization and polling connected; UART/VirtIO preserved')
	println('SHA256 ${sha256.sum(data).hex()}  ${path_value(p.positional[0]).all_after_last('/')}')
}
