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
		else { return error('unknown Android host operation ' + operation) }
	}
	return encode(result)
}

pub fn error_json(err IError) string {
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
