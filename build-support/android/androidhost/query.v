module androidhost

import json2
import encoding.hex

fn text(row map[string]Value, name string) !string {
	value := field(row, name)
	if value is string { return value }
	return error('TypeError: expected string query field ' + name)
}

fn flag(row map[string]Value, name string) bool {
	value := field(row, name)
	return value is bool && value as bool
}

pub fn query(request string) !string {
	row := json2.decode[Value](request, strict: true)!.object()
	operation := text(row, 'operation')!
	result := match operation {
		'split_probe_plan' {
			result := split_probe_plan(unpack_string_value(field(row, 'cases_encoded'))!, field(row, 'cases_type').text(), field(row, 'case_types').items().map(it.text()))!
			pack_string_value(result)
		}
		'needed_libraries', 'runner_digest' { runner_file_query(row, operation)! }
		'digest' { Value(digest(text(row, 'path')!)!) }
		'relative' { Value(relative(field(row, 'name'))!) }
		'elf' {
			required := field(row, 'required')
			check_elf(text(row, 'path')!, required is bool && required as bool)!
			Value(json2.null)
		}
		'regular' {
			regular(text(row, 'path')!)!
			Value(json2.null)
		}
		'inside' { Value(inside(text(row, 'root')!, text(row, 'path')!)!) }
		'configuration_probe_digest' { Value(configuration_probe_digest(text(row, 'support')!)!) }
		'manifest_path' {
			Value(manifest_path(text(row, 'overlay')!, flag(row, 'bionic'), flag(row, 'atl'))!)
		}
		'validate_runtime' {
			Value(validate_runtime(text(row, 'overlay')!, text(row, 'support')!, field(row, 'manifest'), flag(row, 'bionic'), flag(row, 'atl'))!.map(Value(it)))
		}
		'validate_bionic_aliases' {
			validate_bionic_aliases(field(row, 'manifest'), field(row, 'seen').items().map(it.text()))!
			Value(json2.null)
		}
		'validate_atl_metadata' {
			validate_atl_metadata(text(row, 'support')!, field(row, 'manifest'), field(row, 'seen').items().map(it.text()))!
			Value(json2.null)
		}
		'validate_atl_required' {
			validate_atl_required(field(row, 'seen').items().map(it.text()))!
			Value(json2.null)
		}
		'validate_atl_dex_receipt' {
			validate_atl_dex_receipt(text(row, 'name')!, field(row, 'record'), integer(field(row, 'classes')) or { u64(0) }, integer(field(row, 'callsites')) or { u64(0) })!
			Value(json2.null)
		}
		'install_runtime' {
			install_runtime(text(row, 'overlay')!, text(row, 'runtime')!, field(row, 'manifest'), flag(row, 'bionic'), flag(row, 'atl'))!
			Value(json2.null)
		}
		'dex_info' {
			info := dex_info(hex.decode(text(row, 'data')!)!)!
			Value([Value(info.classes.map(Value(it))), Value(info.callsites)])
		}
		'build_advanced_probe', 'advanced_native_elf' { advanced_query(row, operation)! }
		'build_simple_probe' { Value(build_simple_probe(row)!) }
		'archive_simple_classes' {
			archive_simple_classes(text(row, 'source')!, text(row, 'output')!)!
			Value(json2.null)
		}
		'build_probe' {
			build_probe(row)!
			Value(json2.null)
		}
		else { return error('unknown Android host operation ' + operation) }
	}
	return encode(result)
}

pub fn error_json(err IError) string {
	if err is AdvancedExit {
		return encode(Value(map[string]Value{
			'kind':         Value('AdvancedExit')
			'error_fs_hex': Value(err.message.bytes().hex())
		}))
	}
	if err is AdvancedCommandError || err is ProbeCaptureError {
		mut fields := map[string]Value{
			'kind': Value('CalledProcessError')
		}
		if err is AdvancedCommandError {
			fields['args_fs_hex'] = Value(err.arguments.map(Value(it.bytes().hex())))
			fields['returncode'] = Value(err.status)
		} else if err is ProbeCaptureError {
			fields['args_fs_hex'] = Value(err.arguments.map(Value(it.bytes().hex())))
			fields['returncode'] = Value(err.status)
			fields['output'] = Value(err.output)
		}
		return encode(Value(fields))
	}
	if err is ProbeDecodeError {
		return encode(Value(map[string]Value{
			'kind':     Value('UnicodeDecodeError')
			'encoding': Value('utf-8')
			'object':   Value(err.data.hex())
			'start':    Value(err.start)
			'end':      Value(err.end)
			'reason':   Value(err.reason)
		}))
	}
	if err is RunnerFileError {
		return encode(Value(map[string]Value{
			'kind':             Value('RunnerOSError')
			'error':            Value(err.original.msg())
			'errno':            Value(err.original.code())
			'filename_hex':     Value(err.original.filename.bytes().hex())
			'filename_is_path': Value(err.original.filename_is_path)
		}))
	}
	if err is MissingKey {
		return encode(Value(map[string]Value{
			'kind':  Value('KeyError')
			'error': Value(err.key)
		}))
	}
	if err is ProbeFilesystemError {
		return encode(Value(map[string]Value{
			'kind':  Value('PlainOSError')
			'error': Value(err.msg())
		}))
	}
	if err is ProbeExit || err is ZipError {
		return encode(Value(map[string]Value{
			'kind':  Value(if err is ProbeExit { 'SystemExit' } else { 'BadZipFile' })
			'error': Value(err.msg())
		}))
	}
	if err is ProbeCommandError {
		return encode(Value(map[string]Value{
			'kind':       Value('CalledProcessError')
			'args':       Value(err.arguments.map(Value(it)))
			'returncode': Value(err.status)
		}))
	}
	if err is SymlinkLoop {
		return encode(Value(map[string]Value{
			'kind':     Value('SymlinkLoop')
			'filename': Value(err.path)
		}))
	}
	if err is FileError {
		mut fields := map[string]Value{
			'kind':     Value('OSError')
			'error':    Value(err.msg())
			'errno':    Value(err.code())
			'filename': Value(err.filename)
		}
		if err.filename2 != '' { fields['filename2'] = Value(err.filename2) }
		if err.filename_is_path { fields['filename_is_path'] = Value(true) }
		return encode(Value(fields))
	}
	if err is AsciiError {
		return encode(Value(map[string]Value{
			'kind':     Value('UnicodeDecodeError')
			'encoding': Value('ascii')
			'object':   Value(err.bytes.hex())
			'start':    Value(err.start)
			'end':      Value(err.start + 1)
			'reason':   Value(err.msg())
		}))
	}
	if err.msg() in ['StopIteration', 'MemoryError'] {
		return encode(Value(map[string]Value{
			'kind':  Value(err.msg())
			'error': Value('')
		}))
	}
	if err.msg().starts_with('OverflowError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('OverflowError')
			'error': Value(err.msg()[15..])
		}))
	}
	if err.msg().starts_with('IndexError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('IndexError')
			'error': Value(err.msg()[12..])
		}))
	}
	if err.msg().starts_with('struct.error: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('struct.error')
			'error': Value(err.msg()[14..])
		}))
	}
	if err.msg().starts_with('ValueError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('ValueError')
			'error': Value(err.msg()[12..])
		}))
	}
	if err.msg().starts_with('TypeError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('TypeError')
			'error': Value(err.msg()[11..])
		}))
	}
	return encode(Value(map[string]Value{
		'kind':  Value('RuntimeError')
		'error': Value(err.msg())
	}))
}
