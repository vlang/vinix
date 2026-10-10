// SPDX-License-Identifier: GPL-2.0-only
module fixturecompiler

import hosttest
import os

pub enum Family {
	ans
	spi
	speakers
	wifi
	smc
	acpi
}

fn host_arch() string {
	$if arm64 {
		return 'arm64'
	} $else {
		return 'amd64'
	}
}

fn choices(family Family) []string {
	return match family {
		.ans { ['ext2', 'platform', 'ans'] }
		.spi { ['keyboard', 'touchpad'] }
		.wifi { ['protocol', 'platform', 'ctl'] }
		else { []string{} }
	}
}

fn generate(family Family, arguments hosttest.Arguments) ! {
	root := hosttest.root()
	arch := arguments.options['--arch'] or { host_arch() }
	output := hosttest.module_resolve(arguments.positional[0])!
	if family == .acpi && '--arch' !in arguments.options {
		return error('--arch is required')
	}
	mut defines := if family == .speakers { []string{} } else { ['nofloat'] }
	if '--entry' in arguments.options {
		defines << match family {
			.ans { 'ans_ext2_entry' }
			.spi { 'spi_entry' }
			.speakers { 'speakers_entry' }
			.wifi { 'wifi_fixture_entry' }
			else { '' }
		}
	}
	if '--guest' in arguments.options {
		defines << match family {
			.ans { 'ans_fixture_guest' }
			.spi { 'spi_guest' }
			.speakers { 'speakers_guest' }
			.wifi { 'wifi_fixture_guest' }
			.smc { 'smc_guest' }
			else { '' }
		}
	}
	if family in [.smc, .acpi] {
		source := os.join_path(root, if family == .smc {
			'tests/apple_smc/fixture'
		} else {
			'tests/acpi-sync/nativefixture'
		})
		hosttest.generate_module(source, output, arch, defines)!
		return
	}
	kinds := choices(family)
	kind := arguments.options['--kind'] or { if kinds.len > 0 { kinds[0] } else { '' } }
	name := if family == .speakers { 'model' } else { kind + 'fixture' }
	relative := match family {
		.ans { 'tests/apple-ans/' + name }
		.spi { 'tests/apple-spi-' + kind + '/' + name }
		.speakers { 'tests/apple-speakers/model' }
		.wifi { 'tests/m1-wifi/' + name }
		else { '' }
	}
	original := os.join_path(root, relative)
	work := hosttest.work_dir('', 'vinix-${family}-fixture-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	source := os.join_path(work, name)
	os.mkdir(source)!
	reference := '--reference' in arguments.options
	for item in os.ls(original)! {
		if item.ends_with('.v') || (family in [.ans, .wifi] && item.ends_with('.v.pending')) {
			if reference && item == 'core.v' {
				continue
			}
			os.cp(os.join_path(original, item), os.join_path(source, item.trim_string_right('.pending')))!
		}
	}
	if reference {
		os.write_file(os.join_path(source, 'native.v'), 'module ${name}\n#include "${kind}-native-abi.h"\nfn C.fflush(voidptr) i32\n')!
		defines << 'spi_reference'
	}
	hosttest.generate_module(source, output, arch, defines)!
}

pub fn run(family Family) {
	mut options := [hosttest.Option{'--arch', true, ['arm64', 'amd64']}]
	kinds := choices(family)
	if kinds.len > 0 {
		options << hosttest.Option{'--kind', true, kinds}
	}
	if family != .acpi {
		options << hosttest.Option{'--guest', false, []string{}}
	}
	if family !in [.smc, .acpi] {
		options << hosttest.Option{'--entry', false, []string{}}
	}
	if family == .spi {
		options << hosttest.Option{'--reference', false, []string{}}
	}
	parsed := hosttest.parse_arguments(os.args[1..], options, 1,
		'Usage: compile-fixture OUTPUT [--arch arm64|amd64] [fixture options]',
		'Generate the maintained ${family} fixture from native V.') or {
		eprintln(err)
		exit(2)
	}
	if family == .acpi && '--arch' !in parsed.options {
		eprintln('--arch is required')
		exit(2)
	}
	generate(family, parsed) or {
		eprintln(err)
		exit(1)
	}
}
