// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import strconv

fn integer(args cachecli.Arguments, name string, fallback int) !int {
	return int(strconv.parse_int(args.value(name, fallback.str()), 10, 32) or { return InputError{'invalid integer for ' + name} })
}

fn status(failure IError) int {
	report_failure(failure)
	if cachecli.cancelled() { return cachecli.interrupt_status() }
	return if failure is InputError { 2 } else { 1 }
}

pub fn vinix_cli(argv []string, kind VinixKind) int {
	mut scalar := if kind == .kernel {
		['--kernel', '--state-dir', '--firmware', '--qemu', '--timeout', '--cc', '--cpus']
	} else {
		['--kernel', '--sysroot', '--state-dir', '--firmware', '--qemu', '--iterations', '--samples',
			'--timeout', '--allocator-check']
	}
	if kind in [.saved_final, .preboot] { scalar << '--original-reference' }
	args := cachecli.arguments(argv, scalar, []string{}, ['--build-only'], 0, 0,
		'usage: run-vinix --kernel FILE --sysroot ROOT --state-dir NEW_DIR [--iterations N --samples N --timeout SECONDS --allocator-check FILE]') or {
		eprintln(err)
		return 2
	}
	kernel := args.required('--kernel') or {
		eprintln(err)
		return 2
	}
	state := args.required('--state-dir') or {
		eprintln(err)
		return 2
	}
	sysroot := if kind == .kernel {
		''
	} else {
		args.required('--sysroot') or {
			eprintln(err)
			return 2
		}
	}
	iterations := integer(args, '--iterations', 200000) or { return status(err) }
	samples := integer(args, '--samples', 7) or { return status(err) }
	timeout := integer(args, '--timeout', if kind == .kernel { 180 } else { 3600 }) or { return status(err) }
	cpus := integer(args, '--cpus', 1) or { return status(err) }
	if timeout <= 0 || (kind != .kernel && (iterations < 1 || iterations > 1000000000 || samples < 5 || samples > 31)) || (kind == .kernel && (cpus < 1 || cpus > 256)) {
		eprintln('invalid iterations, samples, timeout or CPU count')
		return 2
	}
	options := VinixOptions{
		kernel:             kernel
		sysroot:            sysroot
		state:              state
		firmware:           if '--firmware' in args.options {
			resolve(args.value('--firmware', '')) or { return status(err) }
		} else {
			''
		}
		qemu:               args.value('--qemu', 'qemu-system-x86_64')
		cc:                 args.value('--cc', 'x86_64-linux-musl-gcc')
		iterations:         iterations
		samples:            samples
		timeout:            timeout
		cpus:               cpus
		allocator_check:    if '--allocator-check' in args.options {
			resolve(args.value('--allocator-check', '')) or { return status(err) }
		} else {
			''
		}
		original_reference: if '--original-reference' in args.options {
			resolve(args.value('--original-reference', '')) or { return status(err) }
		} else {
			''
		}
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	command, work := prepare_vinix(options, kind) or { return status(err) }
	if '--build-only' in args.options { return 0 }
	capture_vm(command, work, timeout, options.allocator_check != '', kind) or { return status(err) }
	return 0
}

pub fn macos_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--host', '--port', '--user', '--identity', '--gcc', '--guest-sdk',
		'--host-sdk', '--vm-config', '--state-dir', '--iterations', '--samples', '--timeout'], []string{}, []string{}, 0, 0,
		'usage: run-macos --port PORT --user USER --identity FILE --vm-config FILE --state-dir NEW_DIR [--gcc COMPILER --guest-sdk PATH --host-sdk PATH]') or {
		eprintln(err)
		return 2
	}
	for name in ['--port', '--user', '--identity', '--vm-config', '--state-dir'] {
		args.required(name) or {
			eprintln(err)
			return 2
		}
	}
	port := integer(args, '--port', 0) or { return status(err) }
	iterations := integer(args, '--iterations', 200000) or { return status(err) }
	samples := integer(args, '--samples', 7) or { return status(err) }
	timeout := integer(args, '--timeout', 3600) or { return status(err) }
	if iterations < 1 || iterations > 1000000000 || samples < 5 || samples > 31 || timeout <= 0 {
		eprintln('iterations must be 1..1000000000, samples 5..31, timeout positive')
		return 2
	}
	if (args.value('--guest-sdk', '') != '') != ('--host-sdk' in args.options) {
		eprintln('--guest-sdk and --host-sdk must be supplied together')
		return 2
	}
	options := MacOptions{
		host:       args.value('--host', '127.0.0.1')
		port:       port
		user:       args.value('--user', '')
		identity:   args.value('--identity', '')
		gcc:        args.value('--gcc', '/opt/local/bin/gcc-mp-14')
		guest_sdk:  args.value('--guest-sdk', '')
		host_sdk:   if '--host-sdk' in args.options {
			resolve(args.value('--host-sdk', '')) or { return status(err) }
		} else {
			''
		}
		vm_config:  args.value('--vm-config', '')
		state:      args.value('--state-dir', '')
		iterations: iterations
		samples:    samples
		timeout:    timeout
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	run_macos(options) or { return status(err) }
	return 0
}

pub fn kext_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--gcc', '--library-path', '--state-dir', '--vm-config'], []string{}, []string{}, 0, 0,
		'usage: build-macos-kext --state-dir NEW_DIR [--gcc GCC --library-path PATH --vm-config FILE]') or {
		eprintln(err)
		return 2
	}
	state := args.required('--state-dir') or {
		eprintln(err)
		return 2
	}
	options := KextOptions{
		gcc:              args.value('--gcc', 'gcc-mp-14')
		library_path:     args.value('--library-path', '')
		has_library_path: '--library-path' in args.options
		state:            state
		vm_config:        if '--vm-config' in args.options {
			resolve(args.value('--vm-config', '')) or { return status(err) }
		} else {
			''
		}
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	build_kext(options) or { return status(err) }
	return 0
}

pub fn console_cli(argv []string, measure bool) int {
	args := cachecli.arguments(argv, ['--runtime', '--config'], []string{}, []string{}, if measure {
		1
	} else {
		0
	}, if measure { 1 } else { 0 },
		if measure {
			'usage: measure-recorded NEW_STATE --runtime DIR [--config FILE]'
		} else {
			'usage: control --runtime DIR'
		}) or {
		eprintln(err)
		return 2
	}
	runtime := args.required('--runtime') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if measure {
		measure_recorded(resolve(runtime) or { return status(err) }, args.positional[0], args.value('--config', 'tests/alloc-bench/results/2026-10-02/user-macos/config.json')) or { return status(err) }
	} else {
		console_broker(resolve(runtime) or { return status(err) }) or { return status(err) }
	}
	return 0
}
