// SPDX-License-Identifier: GPL-2.0-or-later
// Emit a freestanding V module's C build artifact without the V runtime.
module main

import hosttest
import os

fn option_value(text string) bool {
	if !text.starts_with('-') || text == '-' { return true }
	value := text[1..]
	if value != '' && value.bytes().all(it.is_digit()) { return true }
	return value.count('.') == 1 && value.all_after('.').len > 0
		&& value.all_before('.').bytes().all(it.is_digit()) && value.all_after('.').bytes().all(it.is_digit())
}

fn main() {
	mut transformed := []string{}
	mut positional := false
	for number, argument in os.args[1..] {
		if positional {
			transformed << argument
			continue
		}
		if argument == '--' {
			positional = true
			transformed << argument
			continue
		}
		if argument == '-d' {
			transformed << '--define'
			continue
		}
		if argument.starts_with('-d') {
			value := argument[2..]
			transformed << '--define=' + if value.starts_with('=') { value[1..] } else { value }
			continue
		}
		if argument.starts_with('-h') {
			mut index := 1
			for index < argument.len && argument[index] == `h` { index++ }
			if index < argument.len && argument[index] == `d` {
				if index + 1 < argument.len || (number + 2 < os.args.len && option_value(os.args[number + 2])) {
					transformed << '-h'
				} else {
					transformed << '--define'
				}
				continue
			}
		}
		transformed << argument
	}
	args := hosttest.parse_arguments(transformed, [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--define', true, []string{}},
		hosttest.Option{'--header', true, []string{}},
	], 2,
		'Usage: generate_module.v SOURCE OUTPUT [--arch amd64|arm64] [-d DEFINE] [--header HEADER]',
		"Emit a freestanding V module's C build artifact without the V runtime.") or {
		eprintln(err.msg())
		exit(2)
	}
	mut defines := []string{}
	mut index := 0
	for index < transformed.len {
		argument := transformed[index]
		name := argument.all_before('=')
		if argument == '--' { break }
		if name.starts_with('--') && '--define'.starts_with(name) {
			if argument.contains('=') {
				defines << argument.all_after('=')
			} else {
				index++
				defines << transformed[index]
			}
		} else if name.starts_with('--') && ('--arch'.starts_with(name) || '--header'.starts_with(name)) && !argument.contains('=') {
			index++
		}
		index++
	}
	source := hosttest.module_resolve(args.positional[0]) or {
		eprintln(err)
		exit(1)
	}
	output := hosttest.module_resolve(args.positional[1]) or {
		eprintln(err)
		exit(1)
	}
	arch := if '--arch' in args.options { args.options['--arch'] } else { 'amd64' }
	hosttest.generate_module(source, output, arch, defines) or {
		eprintln(err.msg())
		exit(1)
	}
	if '--header' in args.options {
		header := hosttest.module_resolve(args.options['--header']) or {
			eprintln(err)
			exit(1)
		}
		hosttest.emit_module_header(source, output, header) or {
			eprintln(err.msg())
			exit(1)
		}
	}
}
