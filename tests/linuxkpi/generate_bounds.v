// SPDX-License-Identifier: GPL-2.0-or-later
// Native compiler-boundary controller; imported Python APIs are temporary façades.
module main

import os
import json2
import hosttest

fn request_field(request map[string]json2.Any, name string) !json2.Any {
	return request[name] or { return error('Missing native bounds API field ' + name) }
}

fn serve_api(request_path string, output string) ! {
	request := hosttest.decode_json(os.read_file(request_path)!)!.as_map()
	operation := request_field(request, 'operation')!.str()
	mut result := json2.Any(json2.Null{})
	match operation {
		'generate' {
			metadata := hosttest.generate_bounds(request_field(request, 'source')!.str(),
				request_field(request, 'archive')!.str(), request_field(request, 'output')!.str(),
				request_field(request, 'depfile')!.str(), request_field(request, 'provenance')!.str(),
				request_field(request, 'compiler')!.str(), request_field(request, 'flags')!.as_array().map(it.str()))!
			os.write_file(output, hosttest.bounds_metadata_json(metadata))!
			return
		}
		'command_stamp' {
			result = hosttest.bounds_command_stamp(request_field(request, 'output')!.str(),
				request_field(request, 'compiler')!.str(), request_field(request, 'flags')!.as_array().map(it.str()),
				request_field(request, 'source')!.str(), request_field(request, 'archive')!.str())!
		}
		'make_escape' { result = hosttest.make_escape(request_field(request, 'path')!.str()) }
		'native_flags' {
			result = hosttest.strings(hosttest.bounds_native_flags(request_field(request, 'flags')!.as_array().map(it.str()))!)
		}
		'dependency_paths' {
			result = hosttest.strings(hosttest.dependency_paths(request_field(request, 'data')!.str(), request_field(request, 'output')!.str())!)
		}
		'configuration' {
			result = hosttest.string_map(hosttest.bounds_configuration(request_field(request, 'text')!.str())!)
		}
		'input_snapshot' {
			result = hosttest.bounds_snapshot(request_field(request, 'paths')!.as_array().map(it.str()))!
		}
		'compiler_command' {
			argv, executable := hosttest.bounds_compiler(request_field(request, 'compiler')!.str())!
			result = {
				'command':    json2.Any(hosttest.strings(argv))
				'executable': json2.Any(executable)
			}
		}
		'offsets' {
			mut macros := map[string]string{}
			for name, value in request_field(request, 'macros')!.as_map() {
				macros[name] = value.str()
			}
			header, values := hosttest.bounds_offsets(request_field(request, 'assembly')!.str(), macros)!
			os.write_file(output, '{"header":' + json2.encode(header) + ',"values":' + json2.encode(values) + '}\n')!
			return
		}
		else { return error('Unknown native bounds API operation ' + operation) }
	}
	hosttest.write_json(output, result)!
}

fn negative_option(text string) bool {
	if !text.starts_with('-') || text.len < 2 { return false }
	value := text[1..]
	if value.bytes().all(it.is_digit()) { return true }
	return value.count('.') == 1 && value.all_before('.').bytes().all(it.is_digit())
		&& value.all_after('.').len > 0 && value.all_after('.').bytes().all(it.is_digit())
}

fn parse_options(args []string) !(map[string]string, []string) {
	names := ['--source-dir', '--archive', '--output', '--command-stamp', '--depfile', '--provenance',
		'--cc', '--help']
	mut options := map[string]string{}
	mut flags := []string{}
	mut unknown := []string{}
	mut index := 0
	for index < args.len {
		argument := args[index]
		if argument == '--' {
			flags = args[index + 1..].clone()
			break
		}
		if !argument.starts_with('-') || argument == '-' || negative_option(argument) {
			flags = args[index..].clone()
			break
		}
		name := argument.all_before('=')
		if argument.starts_with('-h') {
			if !argument[1..].bytes().all(it == `h`) {
				return error('argument -h/--help: ignored explicit argument')
			}
			println('Usage: generate_bounds.v [--source-dir DIRECTORY] [--archive ARCHIVE] [--output HEADER | --command-stamp STAMP] [--depfile FILE] [--provenance FILE] [--cc COMPILER] -- NATIVE_FLAGS\n\nDerive Linux bounds from pinned source and the caller’s native C flags.')
			exit(0)
		}
		matching := names.filter(it.starts_with(name))
		if matching.len > 1 { return error('ambiguous option: ' + name) }
		if matching.len == 0 {
			unknown << argument
			index++
			continue
		}
		selected := matching[0]
		if selected == '--help' {
			if argument.contains('=') { return error('argument --help: ignored explicit argument') }
			println('Usage: generate_bounds.v [--source-dir DIRECTORY] [--archive ARCHIVE] [--output HEADER | --command-stamp STAMP] [--depfile FILE] [--provenance FILE] [--cc COMPILER] -- NATIVE_FLAGS\n\nDerive Linux bounds from pinned source and the caller’s native C flags.')
			exit(0)
		}
		mut value := ''
		if argument.contains('=') {
			value = argument.all_after('=')
		} else {
			if index + 1 >= args.len || (args[index + 1].starts_with('-') && args[index + 1] != '-' && !negative_option(args[index + 1])) {
				return error('argument ${selected}: expected one argument')
			}
			index++
			value = args[index]
		}
		options[selected] = if value == '' && selected != '--cc' { '.' } else { value }
		index++
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return options, flags
}

fn generate(options map[string]string, flags []string) ! {
	pin := hosttest.upstream_pin()!
	version := (pin['version'] or { return error('version') }).str()
	source := options['--source-dir'] or { os.join_path(hosttest.upstream_default(), 'linux-' + version) }
	archive := options['--archive'] or { os.join_path(os.dir(source), 'linux-' + version + '.tar.xz') }
	compiler := options['--cc'] or { 'clang' }
	if stamp := options['--command-stamp'] {
		if ['--output', '--depfile', '--provenance'].any(it in options) {
			return error('command stamp mode does not accept generated output paths')
		}
		hosttest.bounds_command_stamp(stamp, compiler, flags, source, archive)!
		return
	}
	output := options['--output'] or { return error('--output or --command-stamp is required') }
	hosttest.generate_bounds(source, archive, output, options['--depfile'] or { output + '.d' },
		options['--provenance'] or { output + '.json' }, compiler, flags)!
	println('Generated ${output} from Linux ${version}')
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--api-request' && os.args[3] == '--api-output' {
		serve_api(os.args[2], os.args[4]) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	options, flags := parse_options(os.args[1..]) or {
		eprintln(err.msg())
		exit(2)
	}
	generate(options, flags) or {
		eprintln('Linux bounds generation failed: ' + err.msg())
		exit(1)
	}
}
