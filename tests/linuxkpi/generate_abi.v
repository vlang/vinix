// SPDX-License-Identifier: GPL-2.0-or-later
// Native declaration and compiler-boundary metadata generator.
module main

import os
import hosttest

fn parse_abi_arguments(args []string) ![]string {
	mut positional := []string{}
	mut unknown := []string{}
	mut source_root := os.join_path(hosttest.root(), 'kernel/linuxkpi')
	mut index := 0
	for index < args.len {
		arg := args[index]
		if arg == '--' { positional << args[index + 1..]; break }
		name := arg.all_before('=')
		if arg.starts_with('-h') {
			if !arg[1..].bytes().all(it == `h`) { return error('argument -h/--help: ignored explicit argument') }
			println('Usage: generate_abi.v SCHEMA OUTPUT [--source-root DIRECTORY]\n\nGenerate LinuxKPI declaration/type-capture adapters from V and structured ABI metadata.')
			exit(0)
		}
		if name.starts_with('--') && '--help'.starts_with(name) {
			if arg.contains('=') { return error('argument --help: ignored explicit argument') }
			println('Usage: generate_abi.v SCHEMA OUTPUT [--source-root DIRECTORY]\n\nGenerate LinuxKPI declaration/type-capture adapters from V and structured ABI metadata.')
			exit(0)
		}
		if name.starts_with('--') && '--source-root'.starts_with(name) {
			if arg.contains('=') { source_root = arg.all_after('=') }
			else {
				if index + 1 >= args.len || (args[index + 1].starts_with('-') && args[index + 1] != '-' &&
					!negative_path(args[index + 1])) { return error('argument --source-root: expected one argument') }
				index++
				source_root = args[index]
			}
			if source_root == '' { source_root = '.' }
		} else if arg.starts_with('-') && arg != '-' && !negative_path(arg) {
			unknown << arg
		} else { positional << arg }
		index++
	}
	if positional.len < 2 { return error('the following arguments are required: schema, output') }
	if positional.len > 2 { unknown << positional[2..] }
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return [positional[0], positional[1], source_root]
}

fn negative_path(text string) bool {
	if !text.starts_with('-') || text.len < 2 { return false }
	value := text[1..]
	if value.bytes().all(it.is_digit()) { return true }
	if value.count('.') != 1 { return false }
	return value.all_before('.').bytes().all(it.is_digit()) &&
		value.all_after('.').len > 0 && value.all_after('.').bytes().all(it.is_digit())
}

fn main() {
	args := parse_abi_arguments(os.args[1..]) or { eprintln(err.msg()); exit(2) }
	hosttest.generate_abi(args[0], args[2], args[1]) or { eprintln(err.msg()); exit(1) }
}
