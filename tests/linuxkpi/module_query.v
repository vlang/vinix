// SPDX-License-Identifier: GPL-2.0-or-later
// Import API transport; all compiler and metadata policies live in hosttest.
module main

import hosttest
import json2
import os

fn request(row map[string]json2.Any) !map[string]json2.Any {
	operation := row['operation'] or { return error('Missing operation') }.str()
	source := row['source'] or { return error('Missing source') }.str()
	if operation == 'scalar' {
		return {
			'value': json2.Any(hosttest.scalar_metadata(source, row['text'] or { return error('Missing text') }.str())!)
		}
	}
	output := row['output'] or { return error('Missing output') }.str()
	if operation == 'header' {
		hosttest.emit_module_header(source, output, row['header'] or { return error('Missing header') }.str())!
		return {
			'value': json2.Any(json2.Null{})
		}
	}
	if operation != 'generate' { return error('Unknown module operation: ' + operation) }
	arch := row['arch'] or { return error('Missing arch') }.str()
	defines := row['defines'] or { return error('Missing defines') }.as_array().map(it.str())
	result := hosttest.generate_module_capture(source, output, arch, defines)!
	return {
		'value':  json2.Any(json2.Null{})
		'stdout': json2.Any(result.stdout)
		'stderr': json2.Any(result.stderr)
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	for {
		line := os.get_raw_line()
		if line == '' { break }
		row := hosttest.decode_json(line) or {
			println(json2.encode({
				'error': json2.Any(err.msg())
			}))
			continue
		}.as_map()
		value := request(row) or {
			mut failure := map[string]json2.Any{
				'error': json2.Any(err.msg())
				'errno': json2.Any(err.code())
			}
			if err is hosttest.ModuleCommandError {
				failure['kind'] = 'CalledProcessError'
				failure['argv'] = hosttest.strings(err.argv)
				failure['returncode'] = err.result.code
				failure['stdout'] = err.result.stdout
				failure['stderr'] = err.result.stderr
			}
			if err is hosttest.ModuleFileError { failure['filename'] = err.filename }
			if err is hosttest.ModuleCopyError {
				failure['kind'] = 'CopyError'
				failure['entries'] = err.entries.map(json2.Any(hosttest.strings([it.source, it.destination, it.message])))
			}
			if err is hosttest.ModuleDecodeError {
				failure['kind'] = 'UnicodeDecodeError'
				failure['data'] = err.data.hex()
				failure['start'] = err.start
				failure['end'] = err.end
				failure['reason'] = err.reason
			}
			println(json2.encode(failure))
			continue
		}
		println(json2.encode(value))
	}
}
