// SPDX-License-Identifier: GPL-2.0-or-later
module main

import winehost
import tools.packages.pkgprotocol
import tools.packages.pkglaunch

fn hosted_gate(values []string) bool {
	mut pointers := []&char{cap: values.len}
	unsafe { pointers.flags |= .noslices }
	defer { unsafe { pointers.free() } }
	for value in values { pointers << &char(value.str) }
	return winehost.package_command_allowed(i32(values.len), unsafe { &&char(pointers.data) })
}

fn hosted_gate_case(values []string, expected bool) ! {
	hosted_options_require(hosted_gate(values) == expected, 'signed hosted argv gate disagrees with expected acceptance')!
	if values.len >= 3 && values[0] == '/usr/bin/vinix-package' && values[1] == 'run-args' {
		mut service_accepts := true
		pkglaunch.validate_arguments(values[1..]) or { service_accepts = false; unsafe { err.free() } }
		hosted_options_require(service_accepts == expected, 'hosted gate disagrees with authoritative account protocol')!
	}
}

fn check_hosted_gate() ! {
	for values in [
		['/usr/bin/vinix-package', 'run', 'app'],
		['/usr/bin/vinix-package', 'run', 'app', hosted_options_document],
		['/usr/bin/vinix-package', 'run-args', 'app', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--file', hosted_options_document, '--data-cwd', '--', '', 'λ; $(literal)', '--file', '--data-cwd', '\n']
	] { hosted_gate_case(values, true)! }
	for values in [
		[]string{}, [''], ['/usr/bin/vinix-package', 'run'],
		['/tmp/vinix-package', 'run-args', 'app', '--'],
		['/usr/bin/vinix-package', 'run-terminal-args', 'app', '--'],
		['/usr/bin/vinix-package', 'run-window', 'app'],
		['/usr/bin/vinix-package', 'install', 'app'],
		['/usr/bin/vinix-package', 'run', 'app', '/a', '/b'],
		['/usr/bin/vinix-package', 'run', 'App'],
		['/usr/bin/vinix-package', 'run', 'app', 'relative'],
		['/usr/bin/vinix-package', 'run-args', '', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app/', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--data-cwd', '--data-cwd', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--uid', '0', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--file'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--file', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--file', '/a\nb', '--'],
		['/usr/bin/vinix-package', 'run-args', 'app', '--file', '/a\x7fb', '--']
	] { hosted_gate_case(values, false)! }
	for length in [128, 129]! {
		id := 'a'.repeat(length)
		hosted_gate_case(['/usr/bin/vinix-package', 'run-args', id, '--'], length == 128)!
		unsafe { id.free() }
	}
	for length in [4096, 4097]! {
		word := 'x'.repeat(length)
		path := '/' + word[1..]
		hosted_gate_case(['/usr/bin/vinix-package', 'run-args', 'app', '--', word], length == 4096)!
		hosted_gate_case(['/usr/bin/vinix-package', 'run-args', 'app', '--file', path, '--'], length == 4096)!
		unsafe { word.free(); path.free() }
	}
	for count in [256, 257]! {
		mut arguments := []string{cap: 800}
		unsafe { arguments.flags |= .noslices }
		for value in ['/usr/bin/vinix-package', 'run-args', 'app', '--']! { arguments << value.clone() }
		for _ in 0 .. count { arguments << ''.clone() }
		hosted_gate_case(arguments, count == 256)!
		pkgprotocol.free_command_values(mut arguments)
		mut documents := []string{cap: 800}
		unsafe { documents.flags |= .noslices }
		for value in ['/usr/bin/vinix-package', 'run-args', 'app']! { documents << value.clone() }
		for _ in 0 .. count { documents << '--file'.clone(); documents << '/'.clone() }
		documents << '--'.clone()
		hosted_gate_case(documents, count == 256)!
		pkgprotocol.free_command_values(mut documents)
	}
	for tail in [4080, 4081]! {
		mut values := []string{cap: 32}
		unsafe { values.flags |= .noslices }
		for value in ['/usr/bin/vinix-package', 'run-args', 'app', '--']! { values << value.clone() }
		for _ in 0 .. 15 { values << 'x'.repeat(4096) }
		values << 'x'.repeat(tail)
		hosted_gate_case(values, tail == 4080)!
		pkgprotocol.free_command_values(mut values)
	}
	mut maximal := []string{cap: 773}
	unsafe { maximal.flags |= .noslices }
	for value in ['/usr/bin/vinix-package', 'run-args', 'app', '--data-cwd']! { maximal << value.clone() }
	for _ in 0 .. 256 { maximal << '--file'.clone(); maximal << '/'.clone() }
	maximal << '--'.clone()
	for _ in 0 .. 256 { maximal << ''.clone() }
	hosted_options_require(maximal.len == 773, 'maximal gate fixture count changed')!
	hosted_gate_case(maximal, true)!
	pkgprotocol.free_command_values(mut maximal)
	hosted_options_require(!winehost.package_command_allowed(3, unsafe { nil }), 'nil argv accepted')!
	mut nil_id := [c'/usr/bin/vinix-package', c'run-args', &char(unsafe { nil }), c'--']!
	hosted_options_require(!winehost.package_command_allowed(4, &nil_id[0]), 'nil ID accepted')!
	$if track_heap ? {
		mut literal := [c'/usr/bin/vinix-package', c'run-args', c'app', c'--', c'']!
		C.vinix_heap_begin()
		for _ in 0 .. 10000 { hosted_options_require(winehost.package_command_allowed(5, &literal[0]), 'repeated parser refused')! }
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		hosted_options_require(kept == 0 && records == 0, 'raw argv parser retained allocations')!
		println('HOSTED OPTIONS 10000 raw argv validations retain 0 bytes / 0 records PASS')
	}
	println('HOSTED OPTIONS raw argv grammar, exact limits and account protocol agreement PASS')
}
