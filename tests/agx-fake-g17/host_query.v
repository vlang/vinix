// SPDX-License-Identifier: GPL-2.0-only
module main

import agxhost
import traceanalysis as j
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
	if operation == 'vm_policy' {
		text := hex.decode(row['text_hex'] or { json2.Any('') }.str())!.bytestr()
		return {
			'prompt': json2.Any(agxhost.vm_shell_prompt(text))
			'pass': json2.Any(agxhost.vm_line_marker(text, false))
			'fail': json2.Any(agxhost.vm_line_marker(text, true))
			'resources': json2.Any(agxhost.vm_resource_states(text).map(json2.Any(it)))
			'missing': json2.Any(agxhost.vm_missing(text, row['command_sent'] or { json2.Any(false) }.bool(), row['pass_seen'] or { json2.Any(false) }.bool(),
				row['fail_seen'] or { json2.Any(false) }.bool(), row['forced_stop'] or { json2.Any(false) }.bool(), row['status'] or { json2.Any(0) }.int(), row['has_status'] or { json2.Any(false) }.bool()).map(json2.Any(it)))
			'exit_code': json2.Any(agxhost.vm_child_exit_code(row['status'] or { json2.Any(0) }.int()))
		}
	}
	if operation == 'vm_available_port' { return agxhost.vm_available_port()! }
	if operation == 'vm_quit_monitor' { return agxhost.vm_quit_monitor((row['path'] or { json2.Any('') }).str())! }
	if operation == 'vm_exit_code' { return agxhost.vm_child_exit_code((row['status'] or { json2.Any(0) }).int()) }
	if operation == 'core_policy' {
		text := hex.decode((row['text_hex'] or { json2.Any('') }).str())!.bytestr()
		missing, failures := agxhost.core_results(text, (row['verification'] or { json2.Any(false) }).bool(),
			(row['amd64'] or { json2.Any(false) }).bool(), (row['has_status'] or { json2.Any(false) }).bool(),
			(row['status'] or { json2.Any(0) }).int(), (row['forced'] or { json2.Any(false) }).bool(), (row['finished'] or { json2.Any(false) }).bool())
		return {'missing': json2.Any(missing.map(json2.Any(it))), 'failures': json2.Any(failures.map(json2.Any(it)))}
	}
	if operation == 'core_amd64' {
		return out.core_amd64((row['iso'] or { json2.Any('') }).str(), (row['qemu'] or { json2.Any('qemu-system-x86_64') }).str(),
			(row['firmware'] or { json2.Any('None') }).str(), (row['timeout_text'] or { json2.Any('300') }).str(),
			(row['timeout_kind'] or { json2.Any('number') }).str(), (row['cpus_text'] or { json2.Any('4') }).str(),
			(row['python'] or { json2.Any('python3') }).str(), (row['child_binding'] or { json2.Any('') }).str())!
	}
	root := (row['root'] or { return error('Missing root') }).str()
	if operation == 'host' {
		out.host_verifier(root, row['machine'] or { json2.Any('') }.str(), row['encoder_reference'] or { json2.Any('') }.str(), row['verifier_reference'] or { json2.Any('') }.str())!
	} else if operation == 'trace_generate' {
		out.generate_trace(root, (row['output'] or { return error('Missing output') }).str(), row['arch'] or { json2.Any('arm64') }.str(), (row['temp_dir'] or { return error('Missing temp_dir') }).str())!
	} else if operation == 'trace_test' {
		out.trace_test(root, (row['baseline'] or { return error('Missing baseline') }).str(), (row['temp_dir'] or { return error('Missing temp_dir') }).str())!
	} else if operation == 'native_fixture' {
		environment := agxhost.native_environment(row['inherited_environment_hex'] or { json2.Any('') }.str())!
		return out.native_fixture(root, row['arch'] or { json2.Any('') }.str(), row['kernel'] or { json2.Any('') }.str(),
			row['state'] or { json2.Any('') }.str(), row['reference'] or { json2.Any('') }.str(), row['fixture'] or { json2.Any('encoder') }.str(),
			row['timeout_text'] or { json2.Any('600') }.str(), row['python'] or { json2.Any('python3') }.str(), environment)!
	} else if operation == 'vm_test' {
		return out.vm_test(root, row['timeout_text'] or { json2.Any('180') }.str(), row['timeout_kind'] or { json2.Any('number') }.str(), row['python'] or { json2.Any('python3') }.str(),
			(row['child_binding'] or { return error('Missing child binding') }).str())!
	} else if operation in ['core_phase', 'core_vm'] {
		if operation == 'core_phase' {
			return out.core_phase(root, (row['guest_init'] or { json2.Any('') }).str(), (row['initramfs'] or { json2.Any('') }).str(),
				(row['state_dir'] or { json2.Any('') }).str(), (row['timeout_text'] or { json2.Any('300') }).str(),
				(row['timeout_kind'] or { json2.Any('number') }).str(), (row['verification'] or { json2.Any(false) }).bool(),
				(row['python'] or { json2.Any('python3') }).str(), (row['child_binding'] or { json2.Any('') }).str(),
				(row['system'] or { json2.Any('Darwin') }).str())!
		}
		return out.core_vm(root, (row['guest_init'] or { json2.Any('') }).str(), (row['initramfs'] or { json2.Any('') }).str(),
			(row['state_dir'] or { json2.Any('') }).str(), (row['timeout_text'] or { json2.Any('300') }).str(),
			(row['timeout_kind'] or { json2.Any('number') }).str(), (row['python'] or { json2.Any('python3') }).str(),
			(row['child_binding'] or { json2.Any('') }).str(), (row['system'] or { json2.Any('Darwin') }).str())!
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
		if err.binary_output {
			response['output_hex'] = hex.encode(err.output.bytes())
		}
	}
	if err is fixturehost.FileError {
		response['kind'] = 'OSError'
		response['errno'] = err.number
		response['filename'] = hex.encode(err.filename.bytes())
		response['filename_path'] = out.path_executable != '' && out.path_executable == err.filename
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
	if err is agxhost.TraceFailure {
		response['kind'] = err.kind
		response['has_argument'] = err.has_argument
		response['argument_text'] = if err.has_argument { j.encode(err.argument, false) } else { 'null' }
		response['tuple_argument'] = err.tuple_argument
	}
	if err is agxhost.NativeFailure {
		response['kind'] = err.kind
		if err.kind == 'NativeResolveError' { response['path_hex'] = hex.encode(err.message.bytes()) }
	}
	if (response['kind'] or { json2.Any('') }).str() == 'CalledProcessError' {
		response['path_arguments'] = out.path_arguments.map(json2.Any(it))
	}
	return response
}

fn evaluate(text string, inherited bool) map[string]json2.Any {
	mut out := agxhost.Transcript{ inherit: inherited }
	mut row := hosttest.decode_json(text) or { return failure(err, out, '') }.as_map()
	for name in ['root', 'output', 'temp_dir', 'encoder_reference', 'verifier_reference', 'baseline', 'kernel', 'state', 'reference', 'python', 'child_binding', 'path', 'guest_init', 'initramfs', 'state_dir', 'iso', 'firmware'] {
		if encoded := row[name + '_hex'] {
			bytes := hex.decode(encoded.str()) or { return failure(err, out, '') }
			row[name] = bytes.bytestr()
		}
	}
	out.host_arch = row['host_arch'] or { json2.Any('') }.str()
	out.python_stdout_buffered = !(row['stdout_line_buffered'] or { json2.Any(true) }).bool()
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
	if os.args.len == 2 && os.args[1] == '--linux-guest-callback' {
		row := hosttest.decode_json(os.get_raw_line()) or { eprintln(err); exit(1) }.as_map()
		value := agxhost.linux_guest(row) or {
			detail := if err is agxhost.GuestBindingFailure { err.value } else { {'message_hex': json2.Any(hex.encode(err.msg().bytes()))} }
			println(json2.encode({'error': json2.Any(detail)}, escape_unicode: true))
			return
		}
		println(json2.encode({'value': json2.Any(value)}))
		return
	}
	if os.args.len == 4 && os.args[1] == '--stop-child-callback' {
		agxhost.vm_stop_child(i32(os.args[2].int()), i32(os.args[3].int()), true) or {
			println(json2.encode(json2.Any(failure(err, agxhost.Transcript{}, 'vm_stop_child'))))
			return
		}
		println('{"value":null}')
		return
	}
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
