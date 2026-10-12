// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2

pub fn saved_entries() !map[string]json2.Any {
	return hosttest.decode_json($embed_file('entries.json').to_string())!.as_map().clone()
}

pub fn saved_arguments(input []string) ![]string {
	if input.len == 0 || input[0] != 'saved' { return input }
	if input.len < 2 { return error('saved native entrypoint required') }
	origin := resolve(input[1])!
	root := hosttest.root()
	if !origin.starts_with(root + '/') { return error('saved entrypoint is outside this checkout') }
	path := origin[root.len + 1..]
	entries := saved_entries()!
	command := entries[path] or { return error('unknown saved entrypoint: ' + path) }.str()
	mut args := input[2..].clone()
	if command == 'collect-verification' {
		if args.len == 0 || args[0] !in ['x86_64', 'aarch64'] { return error('verification architecture required: x86_64 | aarch64') }
		args = ['--arch', args[0], ...args[1..]]
	}
	return [command, origin, ...args]
}
