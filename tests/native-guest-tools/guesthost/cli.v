// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import strconv

pub struct Options {
pub:
	values map[string][]string
}

pub fn (options Options) value(name string, default_value string) string {
	rows := options.values[name]
	return if rows.len > 0 { rows[rows.len - 1] } else { default_value }
}

pub fn (options Options) has(name string) bool { return name in options.values }

pub fn (options Options) integer(name string, default_value int) !int {
	if !options.has(name) { return default_value }
	return strconv.atoi(options.value(name, ''))!
}

pub fn parse(arguments []string, specifications []hosttest.Option, repeated []string, usage string) !Options {
	mut values := map[string][]string{}
	mut unknown := []string{}
	mut index := 0
	for index < arguments.len {
		argument := arguments[index]
		name := argument.all_before('=')
		mut matches := specifications.filter(name.starts_with('--') && it.name.starts_with(name))
		exact := matches.filter(it.name == name)
		if exact.len == 1 { matches = exact.clone() }
		help := name.starts_with('--') && '--help'.starts_with(name)
		if argument == '-h' || (help && matches.len == 0) {
			if argument.contains('=') { return error('argument --help: ignored explicit argument') }
			println(usage)
			exit(0)
		}
		if matches.len > 1 || (help && matches.len > 0 && name != '--help') {
			return error('ambiguous option: ' + name)
		}
		if matches.len != 1 {
			unknown << argument
			index++
			continue
		}
		option := matches[0]
		mut value := 'true'
		if option.value {
			if argument.contains('=') {
				value = argument.all_after('=')
			} else {
				index++
				if index >= arguments.len {
					return error('argument ' + option.name + ': expected one argument')
				}
				value = arguments[index]
				if value.starts_with('-') && !value[1..].bytes().all(it.is_digit()) {
					return error('argument ' + option.name + ': expected one argument')
				}
			}
			if option.choices.len > 0 && value !in option.choices {
				return error('invalid choice for ' + option.name + ': ' + value)
			}
		} else if argument.contains('=') {
			return error('argument ' + option.name + ': ignored explicit argument')
		}
		if option.name in repeated {
			values[option.name] << value
		} else {
			values[option.name] = [value]
		}
		index++
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return Options{values}
}

fn path_option(options Options, name string, default_value string) !string {
	return resolve(options.value(name, default_value))!
}

pub fn controller(arguments []string, family string) int {
	result := command_checked(arguments, family) or {
		eprintln(err.msg())
		return if err.code() == 2 { 2 } else { 1 }
	}
	return result
}

fn command_checked(arguments []string, family string) !int {
	if family in ['poll', 'pagetable', 'exceptions'] { return built_command(arguments, family)! }
	mut options := [hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true }]
	if family != 'console' {
		options << hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] }
	}
	if family == 'hypervisor' { options << hosttest.Option{ name: '--require-vmx' } }
	if family == 'generic' {
		for name in ['--source', '--prebuilt-init', '--expect', '--fail'] {
			options << hosttest.Option{ name: name, value: true }
		}
		options << [hosttest.Option{ name: '--expect-panic' }, hosttest.Option{ name: '--no-network' }]
	}
	parsed := parse(arguments, options, ['--expect', '--fail'], 'Usage: run --arch aarch64|x86_64 [--kernel-dir DIR] [--state-dir DIR] [--timeout SECONDS]') or {
		return error_with_code(err.msg(), 2)
	}
	if family != 'console' && !parsed.has('--arch') {
		return error_with_code('missing required --arch', 2)
	}
	if family in ['console', 'resources'] && !parsed.has('--state-dir') {
		return error_with_code('missing required --state-dir', 2)
	}
	arch := parsed.value('--arch', 'x86_64')
	kernel_dir := path_option(parsed, '--kernel-dir', root() + '/kernel')!
	state := if parsed.has('--state-dir') { path_option(parsed, '--state-dir', '')! } else { '' }
	timeout := parsed.integer('--timeout', if family == 'resources' {
		480
	} else if family == 'generic' {
		180
	} else {
		600
	}) or {
		return error_with_code('invalid integer for --timeout', 2)
	}
	if family != 'resources' && timeout <= 0 { return error_with_code('timeout must be positive', 2) }
	match family {
		'console' {
			return guest(root() + '/tests/amd64-console/guestfixture/core.v', '', state, kernel_dir, arch,
				['TEST console: zero-length and nonblocking reads passed', 'TEST RESULT: PASS'],
				['TEST RESULT: FAIL'], false, false, timeout)!
		}
		'hypervisor' {
			mut expected := ['HYPERVISOR GUEST PASS']
			if parsed.has('--require-vmx') { expected << 'HYPERVISOR EXECUTION PASS' }
			return guest(root() + '/tests/hypervisor/guestfixture/core.v', '', state, kernel_dir, arch,
				expected, ['HYPERVISOR FAIL:'], false, false, timeout)!
		}
		'resources' {
			work := hosttest.work_dir(state, 'vinix-resource-fixture-')!
			init := compile_init(root() + '/tests/kernel-resources/guest.c', work, arch, true)!
			return guest('', init, work + '/guest', kernel_dir, arch, ['KRES PASS'], ['KRES FAIL'], false, true, timeout)!
		}
		'generic' {
			if parsed.has('--source') == parsed.has('--prebuilt-init') {
				return error_with_code('choose exactly one of --source and --prebuilt-init', 2)
			}
			if !parsed.has('--expect') { return error_with_code('missing required --expect', 2) }
			if parsed.values['--expect'].any(it == '') { return error_with_code('expected verdicts must be nonempty', 2) }
			return guest(if parsed.has('--source') { path_option(parsed, '--source', '')! } else { '' },
				if parsed.has('--prebuilt-init') { path_option(parsed, '--prebuilt-init', '')! } else { '' }, state,
				kernel_dir, arch, parsed.values['--expect'], parsed.values['--fail'],
				parsed.has('--expect-panic'), parsed.has('--no-network'), timeout)!
		}
		else { return error('Unknown guest family') }
	}
}
