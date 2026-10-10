// SPDX-License-Identifier: GPL-2.0-or-later
module wifihost

import hosttest
import os

pub fn rename_provider(text string, kind string) string {
	chars := text.runes()
	mut output := []string{}
	mut index := 0
	for index < chars.len {
		if !hosttest.module_word_rune(chars[index]) {
			output << chars[index].str()
			index++
			continue
		}
		start := index
		for index < chars.len && hosttest.module_word_rune(chars[index]) { index++ }
		word := chars[start..index].string()
		output << if word in ['_vinit', '_vcleanup', '_vinit_caller', '_vcleanup_caller',
			'_vno_main_init_caller', '_v3_no_main_initialized'] {
			'wifi_' + kind + '_provider_' + word
		} else {
			word
		}
	}
	return output.join('')
}

pub fn generate(kind string, output string, arch string) ! {
	root := hosttest.root()
	compiler := hosttest.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], '', -1, os.environ())!.stdout
	work := hosttest.work_dir('', if kind == 'control' {
		'vinix-wifi-v-'
	} else {
		'vinix-wifi-provider-'
	})!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	if kind == 'control' {
		hosttest.module_copy_tree(root + '/tools/m1-wifi/core', work + '/wificli')!
		os.write_file(work + '/v.mod', "Module {name: 'wifi_cli'}\n")!
		os.write_file(work + '/entry.v', 'module main\nimport wificli as _\n')!
	} else {
		os.write_file(work + '/v.mod', "Module { name: 'wifi_fixture_provider' }\n")!
		modules := if kind == 'platform' { ['wificore', 'm1core'] } else { ['wificore'] }
		for name in modules {
			source := work + '/apple/wifi/' + name
			os.mkdir_all(source)!
			hosttest.module_copy_file(root + '/kernel/apple/wifi/' + name + '/core.v', source + '/core.v')!
		}
		if kind == 'platform' {
			hosttest.module_copy_file(root + '/tests/m1-wifi/platform_fixture.v', work + '/apple/wifi/m1core/platform.v')!
		}
		os.write_file(work + '/entry.v', 'module main\nimport apple.wifi.' + modules.last() + ' as _\n')!
	}
	argv := [compiler, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o', output, work]
	mut env := os.environ()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	result := hosttest.capture(argv, '', -1, env)!
	print(result.stdout)
	eprint(result.stderr)
	if result.code != 0 { return hosttest.ModuleCommandError{argv, result} }
	text := hosttest.module_read_text(output)!
	updated := if kind == 'control' {
		'#define _POSIX_C_SOURCE 200809L\n#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n' + text
	} else {
		rename_provider(text, kind)
	}
	hosttest.module_write_text(output, updated)!
}
