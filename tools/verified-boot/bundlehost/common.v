// SPDX-License-Identifier: GPL-2.0-or-later
module bundlehost

import fixturehost
import hosttest
import os
import policyhost
import strconv

#include <stdlib.h>

fn C.mkdtemp(&char) &char

pub struct ArgumentError {
pub:
	message string
}

pub fn (e ArgumentError) msg() string { return e.message }

pub fn (e ArgumentError) code() int { return 2 }

fn argument(message string) IError { return ArgumentError{message} }

pub struct Options {
pub:
	values     map[string][]string
	positional []string
}

pub fn (o Options) value(name string, fallback string) string {
	rows := o.values[name]
	return if rows.len > 0 { rows.last() } else { fallback }
}

pub fn (o Options) has(name string) bool { return name in o.values }

pub fn (o Options) require(names []string) ! {
	for name in names { if !o.has(name) { return argument('missing required ' + name) } }
}

pub fn (o Options) integer(name string, fallback int) !int {
	return if o.has(name) {
		strconv.atoi(o.value(name, '')) or { return argument('invalid integer for ' + name) }
	} else {
		fallback
	}
}

pub fn (o Options) count(name string) !u64 {
	text := o.value(name, '').trim_space()
	// Parse decimal syntax before enforcing the image bound, including values
	// larger than a machine integer. Malformed CLI values are argument errors;
	// negative and oversized integers are invalid image geometry.
	digits := if text.starts_with('+') || text.starts_with('-') { text[1..] } else { text }
	if digits.len == 0 || digits[0] == `_` || digits.ends_with('_') || digits.contains('__')
		|| !digits.bytes().all(it.is_digit() || it == `_`) {
		return argument('invalid integer for ' + name)
	}
	if text.starts_with('-') {
		return error('data block count must be a positive, bounded integer')
	}
	return strconv.parse_uint(digits.replace('_', ''), 10, 64) or { return error('data block count must be a positive, bounded integer') }
}

pub fn parse(args []string, specs []hosttest.Option, repeats []string, positions int, usage string) !Options {
	mut values := map[string][]string{}
	mut positional := []string{}
	mut unknown := []string{}
	mut index := 0
	mut after_separator := false
	for index < args.len {
		arg := args[index]
		if !after_separator && arg == '--' {
			after_separator = true
			index++
			continue
		}
		name := arg.all_before('=')
		mut matches := specs.filter(!after_separator && name.starts_with('--') && it.name.starts_with(name))
		exact := matches.filter(it.name == name)
		if exact.len == 1 { matches = exact.clone() }
		help := !after_separator && (arg == '-h' || (name.starts_with('--') && '--help'.starts_with(name)))
		if matches.len > 1 || (help && matches.len > 0 && name != '--help') {
			return argument('ambiguous option: ' + name)
		}
		if help {
			if arg.contains('=') { return argument('argument --help: ignored explicit argument') }
			println(usage)
			exit(0)
		}
		if matches.len == 1 {
			spec := matches[0]
			mut value := 'true'
			if spec.value {
				if arg.contains('=') {
					value = arg.all_after('=')
				} else {
					index++
					if index >= args.len {
						return argument('argument ' + spec.name + ': expected one argument')
					}
					value = args[index]
					if value.starts_with('-') && value != '-' && !value[1..].bytes().all(it.is_digit()) {
						return argument('argument ' + spec.name + ': expected one argument')
					}
				}
				if spec.choices.len > 0 && value !in spec.choices {
					return argument('invalid choice for ' + spec.name + ': ' + value)
				}
			} else if arg.contains('=') {
				return argument('argument ' + spec.name + ': ignored explicit argument')
			}
			if spec.name in repeats {
				values[spec.name] << value
			} else {
				values[spec.name] = [value]
			}
		} else if positional.len < positions && (after_separator || !arg.starts_with('-') || arg == '-') {
			positional << if arg == '' { '.' } else { arg }
		} else {
			unknown << arg
		}
		index++
	}
	if positional.len != positions { return argument('missing required positional argument') }
	if unknown.len > 0 { return argument('unrecognized arguments: ' + unknown.join(' ')) }
	return Options{values, positional}
}

pub fn root() string { return hosttest.root() }

pub fn absolute(path string) string {
	return if os.is_abs_path(path) {
		path
	} else {
		os.getwd() + '/' + if path == '' { '.' } else { path }
	}
}

pub fn mkdirs(path string) ! {
	if os.is_dir(path) { return }
	if os.exists(path) || os.is_link(path) { return error('Not a directory: ' + path) }
	mkdirs(os.dir(path))!
	os.mkdir(path)!
}

pub fn temporary(parent string, prefix string) !string {
	mkdirs(parent)!
	mut pattern := (parent + '/' + prefix + 'XXXXXX\x00').bytes()
	pointer := unsafe { C.mkdtemp(&char(pattern.data)) }
	if pointer == unsafe { nil } { return os.error_posix() }
	return unsafe { pointer.vstring().clone() }
}

pub fn retire(path string) {
	if !os.exists(path) && !os.is_link(path) { return }
	hosttest.remove_work_dir(path) or { eprintln(err) }
}

pub fn run(argv []string) ! { policyhost.inherited(argv)! }

pub fn run_in(argv []string, directory string) ! {
	policyhost.owned_inherited_environment(argv, policyhost.environment(), policyhost.caller_arch(), directory)!
}

pub fn capture(argv []string) !string { return policyhost.capture(argv) }

pub fn quiet(argv []string) ! {
	result := fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), '', -1, policyhost.command_interrupted, false)!
	if result.status != 0 {
		return error('Command failed: ' + hosttest.shell_join(argv) + '\n' + result.stderr)
	}
}

pub fn cli(family string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	dispatch(family, args) or {
		eprintln('ERROR: ' + err.msg())
		return if policyhost.command_interrupted() || err.code() == 130 {
			130
		} else if err is ArgumentError {
			2
		} else {
			1
		}
	}
	return 0
}
