// SPDX-License-Identifier: BSD-2-Clause
module main

import fixturehost
import encoding.hex
import hosttest
import json2
import os

fn field(row map[string]json2.Any, name string) !string {
	return hex.decode((row[name] or { return error('Missing ' + name) }).str())!.bytestr()
}

fn request(line string) !json2.Any {
	row := hosttest.decode_json(line)!.as_map()
	operation := (row['operation'] or { return error('Missing operation') }).str()
	if operation == 'original' { return fixturehost.original_source()!.bytes().hex() }
	if operation == 'stage' {
		fixturehost.stage_pending(field(row, 'source')!, field(row, 'target')!)!
		return json2.Null{}
	}
	output := field(row, 'output')!
	arch := (row['arch'] or { return error('Missing arch') }).str()
	if operation == 'generate' {
		fixturehost.generate(output, arch)!
		return json2.Null{}
	}
	kind := (row['kind'] or { return error('Missing kind') }).str()
	if operation == 'prepare' {
		fixturehost.prepare(kind, output, arch, (row['guest'] or { json2.Any(false) }).bool())!
		return if kind == 'touch' {
			json2.Any(json2.Null{})
		} else {
			json2.Any((output + '/' + kind + 'fixture-api.h').bytes().hex())
		}
	}
	if operation == 'native' {
		if reference := row['reference'] {
			fixturehost.native_helper(kind, output, arch, reference.str())!
		} else {
			fixturehost.native_build(kind, output, arch)!
		}
		return json2.Null{}
	}
	if operation == 'host' {
		fixturehost.host(kind, output, field(row, 'cc')!, arch)!
		return json2.Null{}
	}
	return error('Unknown fixture operation: ' + operation)
}

fn failure(err IError) json2.Any {
	if err is fixturehost.CopyFileError {
		return {
			'kind':   json2.Any(err.kind)
			'source': json2.Any(err.source.bytes().hex())
			'target': json2.Any(err.target.bytes().hex())
		}
	}
	if err is fixturehost.FileError {
		return {
			'kind':     json2.Any('OSError')
			'error':    json2.Any(err.msg())
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is fixturehost.CommandError {
		return {
			'kind':          json2.Any('CalledProcessError')
			'args':          json2.Any(err.argv.map(json2.Any(it.bytes().hex())))
			'returncode':    json2.Any(err.status)
			'binary_output': json2.Any(err.binary_output)
			'output':        if err.inherited {
				json2.Any(json2.Null{})
			} else if err.binary_output {
				json2.Any(err.output.bytes().hex())
			} else {
				json2.Any(err.output)
			}
		}
	}
	if err is hosttest.ModuleFileError {
		return {
			'kind':     json2.Any('OSError')
			'error':    json2.Any(os.get_error_msg(err.number))
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is hosttest.ModuleCommandError {
		print(err.result.stdout)
		eprint(err.result.stderr)
		return {
			'kind':       json2.Any('CalledProcessError')
			'args':       json2.Any(err.argv.map(json2.Any(it.bytes().hex())))
			'returncode': json2.Any(err.result.code)
			'output':     json2.Any(json2.Null{})
		}
	}
	if err is hosttest.ModuleDecodeError {
		return {
			'kind':  json2.Any('UnicodeDecodeError')
			'data':  json2.Any(err.data.hex())
			'start': json2.Any(err.start)
			'end':   json2.Any(err.end)
			'error': json2.Any(err.reason)
		}
	}
	if err.msg().starts_with('Symlink loop from ') {
		return {
			'kind':     json2.Any('PathLoopError')
			'filename': json2.Any(err.msg().all_after('Symlink loop from ').bytes().hex())
		}
	}
	return {
		'kind':  json2.Any('ValueError')
		'error': json2.Any(err.msg())
	}
}

fn run() ! {
	if os.args.len < 3 { return error('Expected fixture kind and operation') }
	kind := os.args[1]
	operation := os.args[2]
	if operation == 'original' {
		print(fixturehost.original_source()!)
		return
	}
	if os.args.len < 5 { return error('Expected source/output and architecture/target') }
	output := os.args[3]
	arch := os.args[4]
	if operation == 'stage' {
		fixturehost.stage_pending(output, arch)!
		return
	}
	if operation == 'generate' {
		fixturehost.generate(output, arch)!
		return
	}
	if kind !in ['signal', 'touch', 'restart', 'nanosleep', 'blocked', 'poll', 'epoll', 'int'] {
		return error('Unknown core fixture: ' + kind)
	}
	if operation == 'prepare' {
		fixturehost.prepare(kind, output, arch, os.args.len > 5 && os.args[5] == 'guest')!
	} else if operation == 'native' {
		fixturehost.prepare(kind, output, arch, true)!
		fixturehost.native_build(kind, output, arch)!
	} else if operation == 'native-only' {
		fixturehost.native_build(kind, output, arch)!
	} else if operation == 'host' {
		fixturehost.host(kind, output, if os.args.len > 5 { os.args[5] } else { 'clang' }, arch)!
	} else {
		return error('Unknown fixture operation: ' + operation)
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' {
		fixturehost.install(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] == '--command' {
		value := request(os.args[3]) or {
			fixturehost.write(os.args[2], json2.encode(failure(err)) + '\n') or {
				eprintln(err)
				exit(1)
			}
			return
		}
		fixturehost.write(os.args[2], json2.encode({
			'result': value
		}) + '\n') or {
			eprintln(err)
			exit(1)
		}
		return
	}
	run() or {
		eprintln(err)
		exit(1)
	}
}
