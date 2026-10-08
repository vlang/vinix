// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import fixturehost
import hostfixturebuild
import hosttest
import json2
import os

fn path(row map[string]json2.Any, name string) !string {
	return hex.decode(row[name + '_hex']!.str())!.bytestr()
}

fn request(row map[string]json2.Any) !map[string]json2.Any {
	operation := row['operation']!.str()
	if operation == 'existing' {
		return {'value': json2.Any(hostfixturebuild.existing(path(row, 'source')!).bytes().hex())}
	}
	if operation == 'groups' { return {'value': json2.Any(hostfixturebuild.groups.map(json2.Any(hosttest.strings(it))))} }
	if operation == 'allocation' { return {'value': json2.Any(hostfixturebuild.suite_allocation(row['text']!.str()))} }
	if operation == 'namespace' {
		failure := row['template_error'] or { json2.Any(map[string]json2.Any{}) }.as_map()
		if failure.len != 0 { return hostfixturebuild.TemplateFailure{failure} }
		return {'value': json2.Any(hostfixturebuild.model_namespace(row['text']!.str(), row['name']!.str(), row['template']!.as_array()))}
	}
	if operation == 'suite' {
		hostfixturebuild.build_suite(path(row, 'source')!, row['arch']!.str(), row['sanitize']!.bool(), hostfixturebuild.environment(row['environment_hex']!.str())!, row['host_arch']!.str())!
		return {'value': json2.Any(json2.Null{})}
	}
	if operation != 'generate' { return error('Unknown host fixture operation: ' + operation) }
	result := hostfixturebuild.generate_template(path(row, 'source')!, path(row, 'output')!, row['arch']!.str(), row['shared_model']!.bool(), row['template'] or { json2.Any([]json2.Any{}) }.as_array(), row['template_error'] or { json2.Any(map[string]json2.Any{}) }.as_map())!
	return {'value': json2.Any(json2.Null{}), 'stdout': json2.Any(result.stdout), 'stderr': json2.Any(result.stderr)}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		hosttest.module_copy_file(os.executable(), os.args[2]) or { eprintln(err); exit(1) }
		os.chmod(os.args[2], 0o700) or { eprintln(err); exit(1) }
		return
	}
	for {
		line := if os.args.len == 4 && os.args[1] == '--request' { os.args[3] } else { os.get_raw_line() }
		if line == '' { break }
		row := hosttest.decode_json(line) or { println(json2.encode({'error': json2.Any(err.msg())})); continue }.as_map()
		value := request(row) or {
			mut failure := map[string]json2.Any{'error': json2.Any(err.msg()), 'errno': json2.Any(err.code())}
			if err is hosttest.ModuleCommandError {
				failure['kind'] = 'CalledProcessError'
				failure['argv'] = hosttest.strings(err.argv)
				failure['returncode'] = err.result.code
				failure['stdout'] = err.result.stdout
				failure['stderr'] = err.result.stderr
			}
			if err is hosttest.ModuleFileError { failure['filename_hex'] = err.filename.bytes().hex() }
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
			if err is hostfixturebuild.HostFailure { failure['kind'] = err.kind }
			if err is hostfixturebuild.TemplateFailure { failure = err.fields.clone(); failure['error'] = err.msg(); failure['kind'] = 'TemplateError' }
			if err is fixturehost.FileError { failure['filename_hex'] = err.filename.bytes().hex() }
			if err is fixturehost.CommandError {
				failure['kind'] = 'CalledProcessError'
				failure['argv'] = hosttest.strings(err.argv)
				failure['returncode'] = err.status
				failure['stdout'] = ''
				failure['stderr'] = ''
				if !err.inherited { failure['output'] = err.output }
			}
			if os.args.len == 4 && os.args[1] == '--request' { os.write_file(os.args[2], json2.encode(failure)) or { eprintln(err); exit(1) }; return }
			println(json2.encode(failure))
			continue
		}
		if os.args.len == 4 && os.args[1] == '--request' { os.write_file(os.args[2], json2.encode(value)) or { eprintln(err); exit(1) }; return }
		println(json2.encode(value))
	}
}
