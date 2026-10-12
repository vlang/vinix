// SPDX-License-Identifier: GPL-2.0-or-later
module androidfixtures

import json2
import hosttest
import os
import runtimefixture

fn root() string { return hosttest.root() }

pub fn fixture_child(mode string, selection string) ! {
	match mode {
		'--child-runtime' { runtimefixture.run(selection)! }
		'--child-atl' { runtimefixture.run_atl(selection)! }
		'--child-boot' { runtimefixture.run_boot(selection)! }
		'--child-musl' { runtimefixture.run_musl(selection)! }
		else { return error('unknown native fixture child') }
	}
}

pub fn fixtures_cli(argv []string) !int {
	if argv.len == 0 { return error('fixtures needs the original suite name') }
	suite := argv[0]
	mut cases := []string{}
	if suite == 'art-runtime-test' {
		groups := json2.decode[map[string]json2.Any](os.read_file(root() + '/tests/android/runtimefixture/cases.json')!)!['groups']!.as_map()
		for name in ['RuntimeTests', 'BionicTests', 'AtlTests'] { cases << groups[name]!.as_array().map(name + '.' + it.str()) }
	} else if suite in ['bootclasspath-test', 'musl-runtime-test'] {
		name := if suite == 'bootclasspath-test' { 'BootclasspathTests' } else { 'MuslRuntimeTests' }
		file := if suite == 'bootclasspath-test' { 'boot' } else { 'musl' }
		methods := json2.decode[map[string]json2.Any](os.read_file(root() + '/tests/android/runtimefixture/' + file + '-cases.json')!)!['methods']!.as_array()
		cases = methods.map(name + '.' + it.str())
	} else { return error('unknown original native fixture suite: ' + suite) }
	mut filters := []string{}
	mut patterns := []string{}
	mut index := 1
	for index < argv.len {
		arg := argv[index]
		if arg in ['-v', '--verbose', '-q', '--quiet', '-f', '--failfast'] { index++; continue }
		if arg == '-k' {
			index++
			if index == argv.len { return error('missing fixture substring') }
			patterns << argv[index]
		} else if arg in ['-h', '--help'] {
			println('usage: ' + suite + ' [CLASS[.METHOD] ...] [-k SUBSTRING] [-v|-q]')
			return 0
		} else if arg.starts_with('-') { return error('unrecognized fixture option: ' + arg) }
		else { filters << arg }
		index++
	}
	for filter in filters { if !cases.any(it == filter || it.starts_with(filter + '.')) { return error('unknown native fixture selection: ' + filter) } }
	os.setenv('VINIX_RUNTIME_FIXTURE_NATIVE', os.executable(), true)
	mut count := 0
	for name in cases {
		if filters.len > 0 && !filters.any(name == it || name.starts_with(it + '.')) { continue }
		if patterns.len > 0 && !patterns.any(name.contains(it)) { continue }
		match name.all_before('.') {
			'AtlTests' { runtimefixture.run_atl_guarded(name)! }
			'BootclasspathTests' { runtimefixture.run_boot_guarded(name)! }
			'MuslRuntimeTests' { runtimefixture.run_musl_guarded(name)! }
			else { runtimefixture.run_guarded(name)! }
		}
		count++
	}
	println('Native ' + suite + ': ' + count.str() + ' cases PASS')
	return 0
}
