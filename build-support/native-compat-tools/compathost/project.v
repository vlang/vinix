// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import hosttest
import policyhost

fn project(source string, name string, destination string, arch string, globals bool, nofloat bool, defines []string) ! {
	work := hosttest.work_dir('', 'vinix-compat-project-')!
	defer { retire(work) }
	hosttest.module_copy_tree(source, work + '/' + name)!
	if name == 'winehost' {
		hosttest.module_copy_tree(root() + '/tools/packages/x11auth', work + '/x11auth')!
	}
	write(work + '/v.mod', "Module { name: '" + if globals { 'security_core' } else { 'x11_bridge' } + "' }\n")!
	write(work + '/entry.v', 'module main\nimport ' + name + ' as _\n')!
	v := output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
	mut argv := [v]
	if globals { argv << '-enable-globals' }
	argv << ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers']
	if nofloat { argv << '-nofloat' }
	argv << ['-gc', 'none', '-manualfree', '-o', destination]
	for define in defines { argv << ['-d', define] }
	argv << work
	mut env := policyhost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	fixturehost.inherited_command_environment_preferred(argv, env, policyhost.caller_arch())!
}

const scaffold_warnings = '#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n'

fn security_core(tool string, destination string, arch string, defines []string) ! {
	source, module_name := match tool {
		'mac' { root() + '/tools/security-mac/core', 'maccli' }
		'sandbox' { root() + '/tools/sandbox/core', 'sandboxcore' }
		'audit' { root() + '/tools/security-audit/core', 'auditcore' }
		else { return error('Unknown security core') }
	}
	project(source, module_name, destination, arch, true, true, defines)!
	checks := match tool {
		'mac' {
			[['VINIX_MAC_DOMAINS', '16'], ['VINIX_MAC_TYPES', '32'], ['VINIX_MAC_LABEL_TYPES',
				'29'], ['VINIX_MAC_ALL', '511']]
		}
		'sandbox' {
			[['sizeof(struct sb_cap_data)', '12'], ['sizeof(sandboxcore__CapHeader)', '8'],
				['SB_MAX_PATHS', '127'], ['SB_MAX_ENV', '64']]
		}
		else { [['sizeof(sig_atomic_t)', 'sizeof(int)'], ['sizeof(struct record)', '120']] }
	}
	mut layout := ''
	for pair in checks {
		layout += '\n_Static_assert(' + pair[0] + ' == ' + pair[1] + ', "native ' + tool + ' ABI");'
	}
	if tool == 'audit' { layout += '\n_Static_assert(PATH_MAX <= 4096, "bounded audit path ABI");' }
	write(destination, scaffold_warnings + read(destination)! + layout + '\n')!
}

fn security_compile(args []string) !int {
	mut transformed := []string{}
	mut options := true
	for argument in args {
		if argument == '--' { options = false }
		transformed << if options && argument == '-d' {
			'--define'
		} else if options && argument.starts_with('-d') {
			'--define=' + argument[2..].trim_left('=')
		} else {
			argument
		}
	}
	parsed := hosttest.parse_arguments_choices(transformed, [
		hosttest.Option{ name: '--arch', value: true, choices: ['amd64', 'arm64'] },
		hosttest.Option{ name: '--define', value: true },
	], 2, [['mac', 'sandbox', 'audit'], []string{}],
		'Usage: compile-v-core {mac|sandbox|audit} OUTPUT [--arch amd64|arm64] [-d DEFINE]', 'Generate native V security utility cores.') or { return error_with_code(err.msg(), 2) }
	mut defines := []string{}
	mut index := 0
	for index < transformed.len {
		argument := transformed[index]
		if argument == '--' { break }
		name := argument.all_before('=')
		if name.starts_with('--') && '--define'.starts_with(name) {
			if argument.contains('=') {
				defines << argument.all_after('=')
			} else {
				index++
				defines << transformed[index]
			}
		} else if name.starts_with('--') && '--arch'.starts_with(name) && !argument.contains('=') {
			index++
		}
		index++
	}
	security_core(parsed.positional[0], resolve(parsed.positional[1])!, if '--arch' in parsed.options {
		parsed.options['--arch']
	} else {
		'amd64'
	}, defines)!
	return 0
}

fn x11_core(tool string, destination string, arch string, no_main bool) ! {
	mut defines := if no_main { ['wine_host_no_main'] } else { []string{} }
	if tool == 'winehost' { defines << 'x11_host_libc' }
	project(root() + '/build-support/xorg-server/' + tool, tool, destination, arch, false, false,
		defines)!
	write(destination, '#define VINIX_XINPUT_V_RUNTIME 1\n' + scaffold_warnings + read(destination)!)!
}

fn x11_compile(args []string) !int {
	parsed := hosttest.parse_arguments_choices(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['amd64', 'arm64'] },
		hosttest.Option{ name: '--no-main' },
	], 2, [['winehost', 'xinputcore'], []string{}],
		'Usage: compile-v-host {winehost|xinputcore} OUTPUT [--arch amd64|arm64] [--no-main]', 'Generate allocation-free V X11 bridge implementations.') or { return error_with_code(err.msg(), 2) }
	x11_core(parsed.positional[0], resolve(parsed.positional[1])!, if '--arch' in parsed.options {
		parsed.options['--arch']
	} else {
		'amd64'
	}, '--no-main' in parsed.options)!
	return 0
}
