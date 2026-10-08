// SPDX-License-Identifier: GPL-2.0-or-later
// Native pinned source fetch/verification CLI and temporary import boundary.
module main

import os
import json2
import hosttest
import upstreamsource

fn api(request_path string, output string) ! {
	request := hosttest.decode_json(os.read_file(request_path)!)!.as_map()
	pin := (request['pin'] or { return error('Missing source pin') }).as_map()
	operation := (request['operation'] or { return error('Missing source operation') }).str()
	mut value := json2.Any(json2.Null{})
	match operation {
		'digest' {
			value = hosttest.file_digest((request['path'] or { return error('path') }).str())!
		}
		'selected' {
			value = upstreamsource.selected((request['name'] or { return error('name') }).str(), pin)!
		}
		'verify' {
			hosttest.verify_upstream((request['root'] or { return error('root') }).str(), pin)!
		}
		'fetch' {
			value = upstreamsource.fetch((request['base'] or { return error('base') }).str(), pin)!
		}
		else { return error('Unknown source API operation ' + operation) }
	}
	hosttest.write_json(output, value)!
}

fn negative(text string) bool {
	if !text.starts_with('-') || text.len < 2 { return false }
	number := text[1..]
	return number.bytes().all(it.is_digit()) || (number.count('.') == 1
		&& number.all_before('.').bytes().all(it.is_digit()) && number.all_after('.').len > 0
		&& number.all_after('.').bytes().all(it.is_digit()))
}

fn parse(args []string) ![]string {
	mut command := ''
	mut base := hosttest.upstream_default()
	mut unknown := []string{}
	mut index := 0
	for index < args.len {
		argument := args[index]
		if argument == '--' {
			for item in args[index + 1..] {
				if command == '' { command = item } else { unknown << item }
			}
			break
		}
		name := argument.all_before('=')
		if argument.starts_with('-h') {
			if argument == '-h=' {
				return error_with_code('argument -h/--help: ignored explicit argument', 1)
			}
			if !argument[1..].bytes().all(it == `h`) {
				return error('argument -h/--help: ignored explicit argument')
			}
			println('Usage: upstream_source.v {fetch,verify} [--base DIRECTORY]\n\nFetch and verify Linux sources; never patch the imported driver.')
			exit(0)
		}
		if name.starts_with('--') && '--help'.starts_with(name) {
			if argument.contains('=') { return error('argument --help: ignored explicit argument') }
			println('Usage: upstream_source.v {fetch,verify} [--base DIRECTORY]\n\nFetch and verify Linux sources; never patch the imported driver.')
			exit(0)
		}
		if name.starts_with('--') && '--base'.starts_with(name) {
			if argument.contains('=') {
				base = argument.all_after('=')
			} else {
				if index + 1 >= args.len || (args[index + 1].starts_with('-') && args[index + 1] != '-' && !negative(args[index + 1])) {
					return error('argument --base: expected one argument')
				}
				index++
				base = args[index]
			}
			if base == '' { base = '.' }
		} else if !argument.starts_with('-') || argument == '-' || negative(argument) {
			if command == '' {
				if argument !in ['fetch', 'verify'] {
					return error('argument command: invalid choice: ' + argument)
				}
				command = argument
			} else {
				unknown << argument
			}
		} else {
			unknown << argument
		}
		index++
	}
	if command == '' { return error('the following arguments are required: command') }
	if command !in ['fetch', 'verify'] {
		return error('argument command: invalid choice: ' + command)
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return [command, base]
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--api-request' && os.args[3] == '--api-output' {
		api(os.args[2], os.args[4]) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	args := parse(os.args[1..]) or {
		eprintln(err.msg())
		exit(if err.code() == 1 { 1 } else { 2 })
	}
	pin := hosttest.upstream_pin() or {
		eprintln('Linux source verification failed: ' + err.msg())
		exit(1)
	}
	if args[0] == 'fetch' {
		upstreamsource.fetch(args[1], pin) or {
			eprintln('Linux source verification failed: ' + err.msg())
			exit(1)
		}
	} else {
		hosttest.verify_upstream(os.join_path(args[1], 'linux-' + (pin['version'] or { json2.Any('') }).str()), pin) or {
			eprintln('Linux source verification failed: ' + err.msg())
			exit(1)
		}
	}
}
