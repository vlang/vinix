// SPDX-License-Identifier: GPL-2.0-only
module main

import agxhost
import fixturehost
import hosttest
import encoding.hex
import json2
import os

fn request(row map[string]json2.Any, mut out agxhost.Transcript) !json2.Any {
	operation := (row['operation'] or { return error('Missing operation') }).str()
	if operation == 'imports' {
		return agxhost.forbidden_imports(row['text'] or { json2.Any('') }.str(), row['scale'] or { json2.Any(false) }.bool())
	}
	if operation == 'call_count' {
		return agxhost.allocation_call_count(row['text'] or { json2.Any('') }.str(), row['name'] or { json2.Any('calloc') }.str())
	}
	root := (row['root'] or { return error('Missing root') }).str()
	if operation == 'host' {
		out.host_verifier(root, row['machine'] or { json2.Any('') }.str(), row['encoder_reference'] or { json2.Any('') }.str(), row['verifier_reference'] or { json2.Any('') }.str())!
	} else if operation == 'trace_generate' {
		out.generate_trace(root, (row['output'] or { return error('Missing output') }).str(), row['arch'] or { json2.Any('arm64') }.str(), (row['temp_dir'] or { return error('Missing temp_dir') }).str())!
	} else {
		return error('Unknown AGX host operation ' + operation)
	}
	return json2.Null{}
}

fn failure(err IError, out agxhost.Transcript, operation string) map[string]json2.Any {
	mut response := {
		'error':  json2.Any(err.msg())
		'stdout': json2.Any(out.stdout)
		'stderr': json2.Any(out.stderr)
		'kind':   json2.Any(if operation == 'host' { 'RuntimeError' } else { 'ValueError' })
	}
	if err is agxhost.CommandFailure {
		response['kind'] = 'CalledProcessError'
		response['argv'] = hosttest.strings(err.argv.map(hex.encode(it.bytes())))
		response['returncode'] = err.result.code
		response['output'] = json2.Null{}
	}
	if err is fixturehost.CommandError {
		response['kind'] = 'CalledProcessError'
		response['argv'] = hosttest.strings(err.argv.map(hex.encode(it.bytes())))
		response['returncode'] = err.status
		response['output'] = if err.inherited {
			json2.Any(json2.Null{})
		} else {
			json2.Any(err.output)
		}
	}
	if err is fixturehost.FileError {
		response['kind'] = 'OSError'
		response['errno'] = err.number
		response['filename'] = hex.encode(err.filename.bytes())
	}
	if err is hosttest.ModuleFileError {
		response['kind'] = 'OSError'
		response['errno'] = err.number
		response['filename'] = hex.encode(err.filename.bytes())
	}
	if err is hosttest.ModuleCopyError {
		response['kind'] = 'CopyError'
		response['entries'] = err.entries.map(json2.Any(hosttest.strings([it.source, it.destination,
			it.message])))
	}
	if err is hosttest.ModuleDecodeError {
		response['kind'] = 'UnicodeDecodeError'
		response['data'] = hex.encode(err.data)
		response['start'] = err.start
		response['end'] = err.end
		response['reason'] = err.reason
	}
	return response
}

fn evaluate(text string, inherited bool) map[string]json2.Any {
	mut out := agxhost.Transcript{ inherit: inherited }
	mut row := hosttest.decode_json(text) or { return failure(err, out, '') }.as_map()
	for name in ['root', 'output', 'temp_dir', 'encoder_reference', 'verifier_reference'] {
		if encoded := row[name + '_hex'] {
			bytes := hex.decode(encoded.str()) or { return failure(err, out, '') }
			row[name] = bytes.bytestr()
		}
	}
	out.host_arch = row['host_arch'] or { json2.Any('') }.str()
	operation := row['operation'] or { json2.Any('') }.str()
	value := request(row, mut out) or {
		if inherited {
			print(out.stdout)
			eprint(out.stderr)
		}
		return failure(err, out, operation)
	}
	if inherited {
		print(out.stdout)
		eprint(out.stderr)
	}
	return {
		'value':  value
		'stdout': json2.Any(out.stdout)
		'stderr': json2.Any(out.stderr)
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		hosttest.module_copy_file(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] == '--command' {
		fixturehost.write(os.args[2], json2.encode(evaluate(os.args[3], true))) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	for {
		line := os.get_raw_line()
		if line == '' { break }
		println(json2.encode(evaluate(line, false)))
	}
}
